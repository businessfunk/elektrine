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
  defp validate_webhook(_params) do
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

    # First try exact email match
    mailbox = Mailbox
              |> where(email: ^recipient)
              |> Repo.one()

    case mailbox do
      nil ->
        # If no exact match, try to find by username across supported domains
        case find_mailbox_by_cross_domain_lookup(recipient) do
          nil ->
            Logger.warning("No mailbox found for recipient: #{recipient}")
            {:error, :no_mailbox_found}
          found_mailbox ->
            {:ok, found_mailbox}
        end
      mailbox ->
        {:ok, mailbox}
    end
  end

  # Attempts to find a mailbox by looking up the username across all supported domains
  defp find_mailbox_by_cross_domain_lookup(email) do
    case extract_username_and_domain(email) do
      {username, domain} ->
        supported_domains = Application.get_env(:elektrine, :email)[:supported_domains] || ["elektrine.com"]
        
        if domain in supported_domains do
          # Try to find a mailbox for this username with any of the supported domains
          import Ecto.Query
          
          like_patterns = Enum.map(supported_domains, fn d -> "#{username}@#{d}" end)
          
          Mailbox
          |> where([m], m.email in ^like_patterns)
          |> Repo.one()
        else
          nil
        end
      _ ->
        nil
    end
  end

  # Extracts username and domain from an email address
  defp extract_username_and_domain(email) do
    case String.split(email, "@") do
      [username, domain] -> {username, domain}
      _ -> nil
    end
  end

  # Stores the incoming message in the database
  defp store_incoming_message(mailbox_id, params) do
    sender_email = params["from"] || params["mail_from"]
    
    # Check if sender is approved
    sender_approved = Email.sender_approved?(sender_email, mailbox_id)
    
    # Base message attributes
    message_attrs = %{
      "message_id" => params["message_id"] || "incoming-#{:rand.uniform(1000000)}",
      "from" => sender_email,
      "to" => params["to"] || params["rcpt_to"],
      "cc" => params["cc"],
      "subject" => params["subject"],
      "text_body" => params["plain_body"] || params["text_body"],
      "html_body" => params["html_body"],
      "status" => "received",
      "read" => false,
      "spam" => is_spam?(params),
      "archived" => false,
      "mailbox_id" => mailbox_id,
      "metadata" => extract_metadata(params),
      "attachments" => process_attachments(params["attachments"]),
      "has_attachments" => has_attachments?(params["attachments"]),
      # Hey.com features
      "screener_status" => if(sender_approved, do: "approved", else: "pending"),
      "sender_approved" => sender_approved
    }
    
    # Apply automatic categorization if not spam
    message_attrs = if not message_attrs["spam"] do
      Email.categorize_message(message_attrs)
    else
      message_attrs
    end
    
    # Convert string keys to atoms for changeset
    message_attrs = for {key, val} <- message_attrs, into: %{} do
      {String.to_existing_atom(key), val}
    end
    
    case Email.create_message(message_attrs) do
      {:ok, message} ->
        # Track email for approved senders
        if sender_approved do
          Email.track_approved_sender_email(sender_email, mailbox_id)
        end
        
        {:ok, message}
        
      error ->
        error
    end
  end

  # Extracts useful metadata from the webhook payload
  defp extract_metadata(params) do
    headers = params["headers"] || %{}
    
    %{
      received_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      spam_score: params["spam_score"] || headers["x-postal-spam-score"],
      spam_threshold: headers["x-postal-spam-threshold"],
      postal_spam_flag: headers["x-postal-spam"],
      attachments: params["attachments"],
      headers: params["headers"]
    }
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Enum.into(%{})
  end

  # Determines if the message is spam based on Postal's spam headers
  defp is_spam?(params) do
    # Check the x-postal-spam header
    headers = params["headers"] || %{}
    
    case headers["x-postal-spam"] do
      "yes" -> true
      "YES" -> true
      # Also check legacy spam field for backwards compatibility
      _ -> 
        case params["spam"] do
          true -> true
          "true" -> true
          1 -> true
          "1" -> true
          _ -> false
        end
    end
  end

  # Processes attachments from webhook payload
  defp process_attachments(nil), do: %{}
  defp process_attachments([]), do: %{}
  defp process_attachments(attachments) when is_list(attachments) do
    attachments
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {attachment, index}, acc ->
      attachment_id = "attachment_#{index}"
      
      processed_attachment = %{
        "filename" => attachment["name"] || attachment["filename"] || "attachment_#{index}",
        "content_type" => attachment["content_type"] || attachment["mime_type"] || "application/octet-stream",
        "size" => attachment["size"] || attachment["data"] && byte_size(attachment["data"]) || 0,
        "content_id" => attachment["content_id"],
        "disposition" => attachment["disposition"] || "attachment",
        "data" => attachment["data"] || attachment["content"], # Base64 encoded data
        "url" => attachment["url"], # If hosted externally
        "hash" => attachment["hash"] || attachment["checksum"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})
      
      Map.put(acc, attachment_id, processed_attachment)
    end)
  end
  defp process_attachments(attachments) when is_map(attachments), do: attachments
  defp process_attachments(_), do: %{}

  # Checks if message has attachments
  defp has_attachments?(nil), do: false
  defp has_attachments?([]), do: false
  defp has_attachments?(attachments) when is_list(attachments), do: length(attachments) > 0
  defp has_attachments?(attachments) when is_map(attachments), do: map_size(attachments) > 0
  defp has_attachments?(_), do: false
end
