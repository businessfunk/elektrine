defmodule Elektrine.Email.Receiver do
  @moduledoc """
  Handles incoming email processing functionality.
  """

  alias Elektrine.Email
  alias Elektrine.Email.Mailbox
  alias Elektrine.Repo

  require Logger

  @doc """
  Processes an incoming email from a webhook.

  This function is designed to be called by a webhook controller
  that receives POST requests from the Postal server when a new
  email is received.

  ## Parameters

    * `params` - The webhook payload from Postal

  ## Returns

    * `{:ok, message}` - If the email was processed successfully
    * `{:error, reason}` - If there was an error
  """
  def process_incoming_email(params) do
    # Validate webhook authenticity
    with :ok <- validate_webhook(params),
         {:ok, mailbox} <- find_recipient_mailbox(params),
         {:ok, message} <- store_incoming_message(mailbox.id, params) do

      # Send notification to any connected LiveViews
      if mailbox do
        Phoenix.PubSub.broadcast!(
          Elektrine.PubSub,
          "user:#{mailbox.user_id}",
          {:new_email, message}
        )
      end

      {:ok, message}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Validates the webhook request authenticity
  defp validate_webhook(params) do
    # In a real implementation, you would verify the webhook signature
    # using the webhook secret defined in your config

    # For development, we'll just accept all webhooks
    :ok
  end

  # Finds the mailbox for the recipient of this email
  defp find_recipient_mailbox(params) do
    recipient = params["rcpt_to"] || params["to"]

    unless recipient do
      Logger.error("Missing recipient in webhook: #{inspect(params)}")
      {:error, :missing_recipient}
    end

    import Ecto.Query

    mailbox = Mailbox
              |> where(email: ^recipient)
              |> Repo.one()

    case mailbox do
      nil ->
        Logger.warn("No mailbox found for recipient: #{recipient}")
        {:error, :no_mailbox_found}
      mailbox ->
        {:ok, mailbox}
    end
  end

  # Stores the incoming message in the database
  defp store_incoming_message(mailbox_id, params) do
    message_attrs = %{
      message_id: params["message_id"] || "incoming-#{:rand.uniform(1000000)}",
      from: params["from"] || params["mail_from"],
      to: params["to"] || params["rcpt_to"],
      cc: params["cc"],
      subject: params["subject"],
      text_body: params["plain_body"] || params["text_body"],
      html_body: params["html_body"],
      status: "received",
      read: false, # New messages start as unread
      mailbox_id: mailbox_id,
      metadata: extract_metadata(params)
    }

    Email.create_message(message_attrs)
  end

  # Extracts useful metadata from the webhook payload
  defp extract_metadata(params) do
    %{
      received_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      spam_score: params["spam_score"],
      attachments: params["attachments"],
      headers: params["headers"]
    }
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Enum.into(%{})
  end
end
