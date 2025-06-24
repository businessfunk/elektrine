defmodule Elektrine.Email.PostalAdapter do
  @moduledoc """
  Swoosh adapter for Postal HTTP API
  """

  use Swoosh.Adapter

  alias Swoosh.Email

  @base_url "https://postal.elektrine.com"
  @api_path "/api/v1/send/message"

  @impl true
  def deliver(%Email{} = email, config) do
    headers = [
      {"Content-Type", "application/json"},
      {"X-Server-API-Key", config[:api_key]}
    ]

    body = build_api_body(email, config)

    case :hackney.request(:post, "#{@base_url}#{@api_path}", headers, body, [:with_body]) do
      {:ok, 200, _headers, response_body} ->
        case Jason.decode(response_body) do
          {:ok, %{"status" => "success", "data" => data}} ->
            {:ok, %{id: data["message_id"], message_id: data["message_id"]}}

          {:ok, %{"status" => "error", "data" => error}} ->
            {:error, error}

          _ ->
            {:error, "Invalid response from Postal API"}
        end

      {:ok, status_code, _headers, response_body} ->
        {:error, "Postal API returned status #{status_code}: #{response_body}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def deliver_many(emails, config) do
    # Deliver emails one by one
    Enum.map(emails, &deliver(&1, config))
  end

  defp build_api_body(email, _config) do
    # Build the JSON body for Postal API
    body = %{
      "to" => format_recipients(email.to),
      "from" => format_from(email.from),
      "subject" => email.subject
    }

    # Add CC if present
    body =
      if email.cc && email.cc != [] do
        Map.put(body, "cc", format_recipients(email.cc))
      else
        body
      end

    # Add BCC if present
    body =
      if email.bcc && email.bcc != [] do
        Map.put(body, "bcc", format_recipients(email.bcc))
      else
        body
      end

    # Add body content
    body =
      cond do
        email.html_body && email.text_body ->
          # Both HTML and plain text
          body
          |> Map.put("html_body", email.html_body)
          |> Map.put("plain_body", email.text_body)

        email.html_body ->
          # HTML only
          Map.put(body, "html_body", email.html_body)

        email.text_body ->
          # Plain text only
          Map.put(body, "plain_body", email.text_body)

        true ->
          # No body?
          body
      end

    Jason.encode!(body)
  end

  defp format_recipients(recipients) when is_list(recipients) do
    recipients
    |> Enum.map(&format_recipient/1)
    |> Enum.join(",")
  end

  defp format_recipient({name, email}) when is_binary(name) and is_binary(email) do
    if name == "" do
      email
    else
      "#{name} <#{email}>"
    end
  end

  defp format_recipient(email) when is_binary(email), do: email

  defp format_from({name, email}) when is_binary(name) and is_binary(email) do
    if name == "" do
      email
    else
      "#{name} <#{email}>"
    end
  end

  defp format_from(email) when is_binary(email), do: email
end
