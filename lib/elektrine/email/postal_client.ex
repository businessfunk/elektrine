defmodule Elektrine.Email.PostalClient do
  @moduledoc """
  Direct client for Postal HTTP API
  """

  require Logger

  @base_url "https://postal.elektrine.com"
  @api_path "/api/v1/send/message"
  @api_key System.get_env("POSTAL_API_KEY")

  def send_email(params) do
    headers = [
      {"Content-Type", "application/json"},
      {"X-Server-API-Key", @api_key}
    ]

    body = build_api_body(params)

    Logger.debug("Sending email via Postal API: #{inspect(params)}")

    case HTTPoison.post("#{@base_url}#{@api_path}", body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"status" => "success", "data" => data}} ->
            Logger.info("Email sent successfully: #{data["message_id"]}")
            {:ok, %{id: data["message_id"], message_id: data["message_id"]}}
          {:ok, %{"status" => "error", "data" => error}} ->
            Logger.error("Postal API error: #{inspect(error)}")
            {:error, error}
          _ ->
            Logger.error("Invalid response from Postal API: #{response_body}")
            {:error, "Invalid response from Postal API"}
        end
      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("Postal API returned status #{status_code}: #{response_body}")
        {:error, "Postal API returned status #{status_code}: #{response_body}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_api_body(params) do
    # Build the JSON body for Postal API
    body = %{
      "to" => params.to,
      "from" => params.from,
      "subject" => params.subject
    }

    # Add CC if present
    body = if params[:cc] && params[:cc] != "" do
      Map.put(body, "cc", params[:cc])
    else
      body
    end

    # Add BCC if present
    body = if params[:bcc] && params[:bcc] != "" do
      Map.put(body, "bcc", params[:bcc])
    else
      body
    end

    # Add body content
    body = cond do
      params[:html_body] && params[:text_body] ->
        # Both HTML and plain text
        body
        |> Map.put("html_body", params[:html_body])
        |> Map.put("plain_body", params[:text_body])

      params[:html_body] ->
        # HTML only
        Map.put(body, "html_body", params[:html_body])

      params[:text_body] ->
        # Plain text only
        Map.put(body, "plain_body", params[:text_body])

      true ->
        # No body?
        body
    end

    Jason.encode!(body)
  end
end
