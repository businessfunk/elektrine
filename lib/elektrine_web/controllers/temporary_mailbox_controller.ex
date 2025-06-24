defmodule ElektrineWeb.TemporaryMailboxController do
  use ElektrineWeb, :controller

  alias Elektrine.Email

  @doc """
  Main entry point for temporary email - creates a new mailbox if none exists in session.
  """
  def index(conn, _params) do
    # Check if user already has a temporary mailbox in the session
    case get_session(conn, :temporary_mailbox_token) do
      nil ->
        # No temporary mailbox yet, create one with the current domain
        domain = get_request_domain(conn)
        {:ok, mailbox} = Email.create_temporary_mailbox(24, domain)

        # Store token in session
        conn = put_session(conn, :temporary_mailbox_token, mailbox.token)

        # Redirect to show with token
        redirect(conn, to: ~p"/temp-mail/#{mailbox.token}")

      token ->
        # User already has a temporary mailbox, redirect to it
        redirect(conn, to: ~p"/temp-mail/#{token}")
    end
  end

  @doc """
  Shows mailbox and messages for a specific temporary mailbox.
  """
  def show(conn, %{"token" => token}) do
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        # Invalid or expired token, clear session and redirect to index
        conn
        |> clear_session()
        |> put_flash(:error, "Temporary mailbox not found or expired.")
        |> redirect(to: ~p"/temp-mail")

      mailbox ->
        # Get messages for this mailbox
        messages = Email.list_messages(mailbox.id, 50)

        # Check if this is the user's mailbox from session
        is_owner = get_session(conn, :temporary_mailbox_token) == token

        render(conn, :show,
          mailbox: mailbox,
          messages: messages,
          is_owner: is_owner,
          expires_at: mailbox.expires_at,
          remaining_time: calculate_remaining_time(mailbox.expires_at)
        )
    end
  end

  @doc """
  Shows a specific message in a temporary mailbox.
  """
  def view_message(conn, %{"token" => token, "id" => id}) do
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        conn
        |> put_flash(:error, "Temporary mailbox not found or expired.")
        |> redirect(to: ~p"/temp-mail")

      mailbox ->
        # Get the specific message
        case Email.get_message(id, mailbox.id) do
          nil ->
            conn
            |> put_flash(:error, "Message not found.")
            |> redirect(to: ~p"/temp-mail/#{token}")

          message ->
            # Mark message as read
            unless message.read do
              {:ok, _} = Email.mark_as_read(message)
            end

            # Check if this is the user's mailbox from session
            is_owner = get_session(conn, :temporary_mailbox_token) == token

            render(conn, :view_message,
              mailbox: mailbox,
              message: message,
              is_owner: is_owner,
              remaining_time: calculate_remaining_time(mailbox.expires_at)
            )
        end
    end
  end

  @doc """
  Extends the expiration time of a temporary mailbox.
  """
  def extend(conn, %{"token" => token}) do
    # Verify this is the user's mailbox from session
    if get_session(conn, :temporary_mailbox_token) != token do
      conn
      |> put_flash(:error, "You don't have permission to extend this mailbox.")
      |> redirect(to: ~p"/temp-mail")
    else
      case Email.get_temporary_mailbox_by_token(token) do
        nil ->
          conn
          |> put_flash(:error, "Temporary mailbox not found or expired.")
          |> redirect(to: ~p"/temp-mail")

        mailbox ->
          # Extend for another 24 hours
          case Email.extend_temporary_mailbox(mailbox.id) do
            {:ok, _updated_mailbox} ->
              conn
              |> put_flash(:info, "Mailbox extended for another 24 hours.")
              |> redirect(to: ~p"/temp-mail/#{token}")

            {:error, _} ->
              conn
              |> put_flash(:error, "Failed to extend mailbox.")
              |> redirect(to: ~p"/temp-mail/#{token}")
          end
      end
    end
  end

  @doc """
  Refreshes the mailbox to check for new messages.
  """
  def refresh(conn, %{"token" => token}) do
    redirect(conn, to: ~p"/temp-mail/#{token}")
  end

  @doc """
  Creates a new temporary mailbox and abandons the old one.
  """
  def new(conn, _params) do
    # Create a new temporary mailbox with the current domain
    domain = get_request_domain(conn)
    {:ok, mailbox} = Email.create_temporary_mailbox(24, domain)

    # Update session
    conn = put_session(conn, :temporary_mailbox_token, mailbox.token)

    # Redirect to new mailbox
    conn
    |> put_flash(:info, "New temporary mailbox created.")
    |> redirect(to: ~p"/temp-mail/#{mailbox.token}")
  end

  @doc """
  Deletes a message from a temporary mailbox.
  """
  def delete_message(conn, %{"token" => token, "id" => id}) do
    # Verify this is the user's mailbox from session
    if get_session(conn, :temporary_mailbox_token) != token do
      conn
      |> put_flash(:error, "You don't have permission to delete messages from this mailbox.")
      |> redirect(to: ~p"/temp-mail")
    else
      case Email.get_temporary_mailbox_by_token(token) do
        nil ->
          conn
          |> put_flash(:error, "Temporary mailbox not found or expired.")
          |> redirect(to: ~p"/temp-mail")

        mailbox ->
          # Get the message
          message = Email.get_message(id, mailbox.id)

          if message do
            # Delete the message
            {:ok, _} = Email.delete_message(message)

            conn
            |> put_flash(:info, "Message deleted successfully.")
            |> redirect(to: ~p"/temp-mail/#{token}")
          else
            conn
            |> put_flash(:error, "Message not found.")
            |> redirect(to: ~p"/temp-mail/#{token}")
          end
      end
    end
  end

  # Helper to extract domain from request
  defp get_request_domain(conn) do
    host =
      case get_req_header(conn, "host") do
        # Remove port if present
        [host] -> String.split(host, ":") |> hd()
        _ -> nil
      end

    # Map known hosts to appropriate email domains
    case host do
      "z.org" ->
        "z.org"

      "www.z.org" ->
        "z.org"

      "elektrine.com" ->
        "elektrine.com"

      "www.elektrine.com" ->
        "elektrine.com"

      _ ->
        # Default to elektrine.com for unknown hosts
        "elektrine.com"
    end
  end

  # Helper to calculate remaining time until expiration
  defp calculate_remaining_time(expires_at) do
    now = DateTime.utc_now()

    case DateTime.compare(expires_at, now) do
      :gt ->
        # Calculate difference in minutes
        diff_seconds = DateTime.diff(expires_at, now, :second)
        hours = div(diff_seconds, 3600)
        minutes = div(rem(diff_seconds, 3600), 60)

        if hours > 0 do
          "#{hours} hours and #{minutes} minutes"
        else
          "#{minutes} minutes"
        end

      _ ->
        "Expired"
    end
  end
end
