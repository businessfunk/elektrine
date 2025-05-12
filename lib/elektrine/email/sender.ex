defmodule Elektrine.Email.Sender do
  @moduledoc """
  Handles email sending functionality.
  """

  alias Elektrine.Email
  alias Elektrine.Email.Postal
  alias Elektrine.Email.Message
  alias Elektrine.Email.Mailbox
  alias Elektrine.Repo

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
         {:ok, postal_response} <- send_via_postal(params),
         {:ok, message} <- store_sent_message(mailbox.id, params, postal_response) do
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

  # Sends the email via Postal API
  defp send_via_postal(params) do
    Postal.send_email(params)
  end

  # Stores the sent message in the database
  defp store_sent_message(mailbox_id, params, postal_response) do
    message_attrs = %{
      message_id: postal_response.message_id,
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