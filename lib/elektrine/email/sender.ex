defmodule Elektrine.Email.Sender do
  @moduledoc """
  Handles email sending functionality.
  """

  alias Elektrine.Email
  alias Elektrine.Email.Mailbox
  alias Elektrine.Mailer
  alias Elektrine.Repo
  import Swoosh.Email

  require Logger

  @doc """
  Sends an email from a user's mailbox.
  
  ## Parameters
  
    * `user_id` - The ID of the user sending the email
    * `params` - Map containing the email parameters:
      * `:from` - Sender's email address (should be one of the user's mailboxes)
      * `:to` - Recipient email address(es) (comma separated string or list)
      * `:cc` - CC recipients (optional)
      * `:bcc` - BCC recipients (optional)
      * `:subject` - Email subject
      * `:text_body` - Plain text body
      * `:html_body` - HTML body (optional)
  
  ## Returns
  
    * `{:ok, message}` - If the email was sent successfully
    * `{:error, reason}` - If there was an error
  """
  def send_email(user_id, params) do
    with {:ok, mailbox} <- get_user_mailbox(user_id),
         {:ok, swoosh_response} <- send_via_swoosh(params),
         {:ok, message} <- store_sent_message(mailbox.id, params, swoosh_response) do
      {:ok, message}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Gets the user's mailbox
  defp get_user_mailbox(user_id) do
    import Ecto.Query

    mailbox = Mailbox
              |> where(user_id: ^user_id)
              |> Repo.one()

    case mailbox do
      nil ->
        Logger.error("User #{user_id} does not have a mailbox")
        {:error, :no_mailbox}
      mailbox ->
        {:ok, mailbox}
    end
  end

  # Sends the email via Postal API or Swoosh
  defp send_via_swoosh(params) do
    # Try Postal API first if not in test/local mode
    if should_use_postal_api?() do
      send_via_postal_api(params)
    else
      send_via_swoosh_adapter(params)
    end
  end
  
  defp should_use_postal_api? do
    # Use Postal API unless we're explicitly using local email
    System.get_env("USE_LOCAL_EMAIL") != "true" && 
    Application.get_env(:elektrine, :env) != :test
  end
  
  defp send_via_postal_api(params) do
    case Elektrine.Email.PostalClient.send_email(params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> 
        Logger.error("Postal API failed, falling back to Swoosh: #{inspect(reason)}")
        send_via_swoosh_adapter(params)
    end
  end
  
  # Original Swoosh sending logic
  defp send_via_swoosh_adapter(params) do
    try do
      email = 
        new()
        |> from(params[:from])
        |> to(params[:to])
        |> subject(params[:subject])
        |> text_body(params[:text_body])
        
      # Add CC if provided
      email = if params[:cc] && String.trim(params[:cc]) != "" do
        cc(email, params[:cc])
      else
        email
      end
      
      # Add BCC if provided  
      email = if params[:bcc] && String.trim(params[:bcc]) != "" do
        bcc(email, params[:bcc])
      else
        email
      end
      
      # Add HTML body if provided
      email = if params[:html_body] do
        html_body(email, params[:html_body])
      else
        email
      end

      case Mailer.deliver(email) do
        {:ok, result} ->
          # Generate a message ID for tracking
          message_id = "swoosh-#{:rand.uniform(1000000)}-#{System.system_time(:millisecond)}"
          {:ok, %{id: result.id || message_id, message_id: message_id}}
        {:error, reason} ->
          Logger.error("Failed to send email via Swoosh: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Error sending email: #{inspect(e)}")
        {:error, e}
    end
  end

  # Stores the sent message in the database
  defp store_sent_message(mailbox_id, params, swoosh_response) do
    message_attrs = %{
      message_id: swoosh_response.message_id,
      from: params[:from],
      to: normalize_recipients(params[:to]),
      cc: normalize_recipients(params[:cc]),
      bcc: normalize_recipients(params[:bcc]),
      subject: params[:subject],
      text_body: params[:text_body],
      html_body: params[:html_body],
      status: "sent",
      read: true, # Sent messages are always marked as read
      mailbox_id: mailbox_id
    }
    
    Email.create_message(message_attrs)
  end
  
  # Normalize recipients to string format
  defp normalize_recipients(nil), do: nil
  defp normalize_recipients(recipients) when is_list(recipients), do: Enum.join(recipients, ", ")
  defp normalize_recipients(recipients), do: recipients
end