defmodule ElektrineWeb.EmailController do
  use ElektrineWeb, :controller

  alias Elektrine.Email
  alias Elektrine.Email.Sender
  alias Elektrine.Email.Message

  def index(conn, _params) do
    conn
    |> redirect(to: ~p"/email/inbox")
  end

  def inbox(conn, params) do
    user = conn.assigns.current_user
    page = Map.get(params, "page", "1") |> String.to_integer()
    per_page = 20

    # Get user's mailbox
    mailbox = Email.get_user_mailbox(user.id)

    # If no mailbox, create one
    mailbox =
      case mailbox do
        nil ->
          {:ok, new_mailbox} = Email.ensure_user_has_mailbox(user)
          new_mailbox

        existing ->
          existing
      end

    # Get messages for the mailbox with pagination
    messages = Email.list_messages(mailbox.id, per_page, (page - 1) * per_page)
    unread_count = Email.unread_count(mailbox.id)

    render(conn, :inbox,
      mailbox: mailbox,
      messages: messages,
      unread_count: unread_count,
      page: page,
      per_page: per_page
    )
  end

  def sent(conn, params) do
    user = conn.assigns.current_user
    page = Map.get(params, "page", "1") |> String.to_integer()
    per_page = 20

    # Get user's mailbox
    mailbox = Email.get_user_mailbox(user.id)

    # If no mailbox, create one
    mailbox =
      case mailbox do
        nil ->
          {:ok, new_mailbox} = Email.ensure_user_has_mailbox(user)
          new_mailbox

        existing ->
          existing
      end

    # Get sent messages for the mailbox with pagination
    import Ecto.Query

    sent_messages =
      Message
      |> where(mailbox_id: ^mailbox.id, status: "sent")
      |> order_by(desc: :inserted_at)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Elektrine.Repo.all()

    render(conn, :sent,
      mailbox: mailbox,
      messages: sent_messages,
      page: page,
      per_page: per_page
    )
  end

  def compose(conn, _params) do
    user = conn.assigns.current_user

    # Get user's mailbox
    mailbox = Email.get_user_mailbox(user.id)

    # If no mailbox, create one
    mailbox =
      case mailbox do
        nil ->
          {:ok, new_mailbox} = Email.ensure_user_has_mailbox(user)
          new_mailbox

        existing ->
          existing
      end

    render(conn, :compose, mailbox: mailbox)
  end

  def send_email(conn, %{"email" => email_params}) do
    user = conn.assigns.current_user

    # Always send from the user's mailbox email
    mailbox = Email.get_user_mailbox(user.id)

    case Sender.send_email(user.id, %{
           from: mailbox.email,
           to: email_params["to"],
           cc: email_params["cc"],
           bcc: email_params["bcc"],
           subject: email_params["subject"],
           text_body: email_params["body"],
           html_body: format_html_body(email_params["body"])
         }) do
      {:ok, _message} ->
        conn
        |> put_flash(:info, "Email sent successfully.")
        |> redirect(to: ~p"/email/sent")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to send email: #{inspect(reason)}")
        |> redirect(to: ~p"/email/compose")
    end
  end

  def view(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    mailbox = Email.get_user_mailbox(user.id)

    # Find the message
    message = Email.get_message(id)

    case message do
      nil ->
        conn
        |> put_flash(:error, "Message not found.")
        |> redirect(to: ~p"/email/inbox")

      message ->
        # Check if the message belongs to the user's mailbox
        if message.mailbox_id == mailbox.id do
          # Mark as read if not already
          unless message.read do
            Email.mark_as_read(message)
          end

          render(conn, :view, message: message, mailbox: mailbox)
        else
          conn
          |> put_flash(:error, "You don't have permission to view this message.")
          |> redirect(to: ~p"/email/inbox")
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    mailbox = Email.get_user_mailbox(user.id)

    message = Email.get_message(id)

    case message do
      nil ->
        conn
        |> put_flash(:error, "Message not found.")
        |> redirect(to: ~p"/email/inbox")

      message ->
        if message.mailbox_id == mailbox.id do
          case Email.delete_message(message) do
            {:ok, _} ->
              conn
              |> put_flash(:info, "Message deleted successfully.")
              |> redirect(to: ~p"/email/inbox")

            {:error, _} ->
              conn
              |> put_flash(:error, "Failed to delete message.")
              |> redirect(to: ~p"/email/inbox")
          end
        else
          conn
          |> put_flash(:error, "You don't have permission to delete this message.")
          |> redirect(to: ~p"/email/inbox")
        end
    end
  end

  def print(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    mailbox = Email.get_user_mailbox(user.id)

    message = Email.get_message(id)

    case message do
      nil ->
        conn
        |> put_flash(:error, "Message not found.")
        |> redirect(to: ~p"/email/inbox")

      message ->
        if message.mailbox_id == mailbox.id do
          # Mark as read if not already
          unless message.read do
            Email.mark_as_read(message)
          end

          conn
          |> put_layout(false)
          |> render(:print, message: message, mailbox: mailbox)
        else
          conn
          |> put_flash(:error, "You don't have permission to view this message.")
          |> redirect(to: ~p"/email/inbox")
        end
    end
  end

  def raw(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    mailbox = Email.get_user_mailbox(user.id)

    message = Email.get_message(id)

    case message do
      nil ->
        conn
        |> put_flash(:error, "Message not found.")
        |> redirect(to: ~p"/email/inbox")

      message ->
        if message.mailbox_id == mailbox.id do
          conn
          |> put_layout(false)
          |> render(:raw, message: message, mailbox: mailbox)
        else
          conn
          |> put_flash(:error, "You don't have permission to view this message.")
          |> redirect(to: ~p"/email/inbox")
        end
    end
  end

  def iframe_content(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    mailbox = Email.get_user_mailbox(user.id)

    message = Email.get_message(id)

    case message do
      nil ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "Message not found")

      message ->
        if message.mailbox_id == mailbox.id do
          # Process the email content to handle encoding issues
          import ElektrineWeb.CoreComponents, only: [process_email_html: 1]
          
          is_html_email = not is_nil(message.html_body)
          
          html_content = if message.html_body do
            # Process HTML body to handle encoding
            process_email_html(message.html_body)
          else
            # For text-only emails, decode and wrap in pre tag
            text = message.text_body || ""
            decoded_text = decode_quoted_printable_text(text)
            "<pre class=\"raw-email-content\">#{Phoenix.HTML.html_escape(decoded_text)}</pre>"
          end
          
          # Different CSS for HTML emails vs plain text/raw emails
          overflow_css = if is_html_email do
            """
            /* Minimal CSS for HTML emails - preserve original styling */
            img {
              max-width: 100%;
              height: auto;
            }
            
            /* Only fix extreme cases on mobile */
            @media (max-width: 768px) {
              table {
                max-width: 100% !important;
              }
            }
            """
          else
            """
            /* Aggressive overflow handling for raw/plain text emails */
            pre.raw-email-content {
              white-space: pre-wrap !important; 
              word-wrap: break-word !important; 
              word-break: break-word !important;
              overflow-wrap: break-word !important;
              overflow-x: auto !important;
              max-width: 100% !important;
              font-family: 'Courier New', Courier, monospace;
              font-size: 12px;
              line-height: 1.4;
              margin: 0;
              padding: 10px;
              background: #f8f9fa;
              border: 1px solid #e9ecef;
              border-radius: 4px;
            }
            """
          end
          
          conn
          |> put_resp_content_type("text/html")
          |> put_resp_header("content-security-policy", "default-src 'self'; img-src * data: https:; style-src 'unsafe-inline' *; font-src *;")
          |> send_resp(200, """
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <base target="_blank">
            <style>
              html, body { 
                margin: 0; 
                padding: 0;
                width: 100%;
                overflow-x: auto;
                overflow-y: auto;
                box-sizing: border-box;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                line-height: 1.6;
                color: #333;
              }
              body {
                padding: 20px;
              }
              
              #{overflow_css}
            </style>
          </head>
          <body>
            #{html_content}
          </body>
          </html>
          """)
        else
          conn
          |> put_resp_content_type("text/html")
          |> send_resp(403, "Forbidden")
        end
    end
  end
  
  # Decode quoted-printable encoded text
  defp decode_quoted_printable_text(text) when is_binary(text) do
    text
    # Remove soft line breaks
    |> String.replace(~r/=\r?\n/, "")
    # Decode =XX sequences  
    |> String.replace(~r/=([0-9A-Fa-f]{2})/, fn match ->
      hex = String.slice(match, 1, 2)
      case Integer.parse(hex, 16) do
        {value, ""} -> <<value>>
        _ -> match
      end
    end)
    # Handle special sequences
    |> String.replace("=3D", "=")
    |> String.replace("=20", " ")
    |> String.replace("=09", "\t")
    # Remove any trailing = signs
    |> String.replace(~r/=\s*$/m, "")
  end
  
  defp decode_quoted_printable_text(text), do: text

  # Converts plain text to simple HTML
  defp format_html_body(nil), do: nil

  defp format_html_body(text) do
    text
    |> String.split("\n")
    |> Enum.map(&("<p>" <> to_string(Phoenix.HTML.html_escape(&1)) <> "</p>"))
    |> Enum.join("")
  end
end
