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

  # Converts plain text to simple HTML
  defp format_html_body(nil), do: nil

  defp format_html_body(text) do
    text
    |> String.split("\n")
    |> Enum.map(&("<p>" <> to_string(Phoenix.HTML.html_escape(&1)) <> "</p>"))
    |> Enum.join("")
  end
end
