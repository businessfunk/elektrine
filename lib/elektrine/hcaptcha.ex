defmodule Elektrine.HCaptcha do
  @moduledoc """
  hCaptcha verification functionality.
  """

  @doc """
  Verifies a hCaptcha response token with the hCaptcha service.
  
  ## Parameters
  
    * `token` - The hCaptcha response token from the frontend
    * `remote_ip` - The user's IP address (optional)
  
  ## Returns
  
    * `{:ok, :verified}` - If the captcha is valid
    * `{:error, reason}` - If the captcha is invalid or verification failed
  
  """
  def verify(token, remote_ip \\ nil) do
    config = Application.get_env(:elektrine, :hcaptcha)
    secret_key = Keyword.get(config, :secret_key)
    verify_url = Keyword.get(config, :verify_url)

    case {secret_key, Mix.env()} do
      {nil, :dev} ->
        # In development, bypass verification if secret key is not set
        {:ok, :verified}
        
      {nil, _} ->
        {:error, :missing_secret_key}

      {_, _} ->
        body = build_verification_body(secret_key, token, remote_ip)
        
        case HTTPoison.post(verify_url, body, [{"Content-Type", "application/x-www-form-urlencoded"}]) do
          {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
            handle_response(response_body)

          {:ok, %HTTPoison.Response{status_code: status_code}} ->
            {:error, {:http_error, status_code}}

          {:error, %HTTPoison.Error{reason: reason}} ->
            {:error, {:network_error, reason}}
        end
    end
  end

  defp build_verification_body(secret_key, token, remote_ip) do
    params = [
      {"secret", secret_key},
      {"response", token}
    ]

    params = 
      case remote_ip do
        nil -> params
        ip -> [{"remoteip", ip} | params]
      end

    URI.encode_query(params)
  end

  defp handle_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"success" => true}} ->
        {:ok, :verified}

      {:ok, %{"success" => false, "error-codes" => error_codes}} ->
        {:error, {:verification_failed, error_codes}}

      {:ok, %{"success" => false}} ->
        {:error, :verification_failed}

      {:error, _} ->
        {:error, :invalid_response}
    end
  end
end