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
    require Logger

    config = Application.get_env(:elektrine, :hcaptcha)
    secret_key = Keyword.get(config, :secret_key)
    verify_url = Keyword.get(config, :verify_url)
    skip_in_dev = Keyword.get(config, :skip_in_dev, false)

    Logger.debug(
      "hCaptcha verification - secret_key present: #{!is_nil(secret_key)}, token length: #{String.length(token || "")}"
    )

    cond do
      # Allow skipping in development if configured
      skip_in_dev and is_nil(secret_key) ->
        Logger.debug("hCaptcha verification skipped in dev")
        {:ok, :verified}

      is_nil(secret_key) ->
        Logger.error("hCaptcha secret key not configured")
        {:error, :missing_secret_key}

      true ->
        body = build_verification_body(secret_key, token, remote_ip)

        case HTTPoison.post(verify_url, body, [
               {"Content-Type", "application/x-www-form-urlencoded"}
             ]) do
          {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
            Logger.debug("hCaptcha API response: #{response_body}")
            handle_response(response_body)

          {:ok, %HTTPoison.Response{status_code: status_code}} ->
            Logger.error("hCaptcha API HTTP error: #{status_code}")
            {:error, {:http_error, status_code}}

          {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.error("hCaptcha API network error: #{inspect(reason)}")
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
