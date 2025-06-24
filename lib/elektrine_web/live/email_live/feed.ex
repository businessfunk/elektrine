defmodule ElektrineWeb.EmailLive.Feed do
  use ElektrineWeb, :live_view

  alias Elektrine.Email

  import ElektrineWeb.EmailLive.EmailHelpers

  @impl true
  def mount(_params, _session, socket) do
    # Get current user from socket assigns (set by auth hooks)
    current_user = socket.assigns.current_user

    # Get user's mailbox
    mailbox = Email.get_user_mailbox(current_user.id)

    if mailbox do
      # Get feed messages
      messages = Email.list_feed_messages(mailbox.id)

      # Stream the messages
      socket =
        socket
        |> assign(:current_user, current_user)
        |> assign(:mailbox, mailbox)
        |> assign(:messages, messages)
        |> assign(:unread_count, Email.unread_count(mailbox.id))
        |> stream(:messages, messages)

      {:ok, socket}
    else
      # Redirect to inbox if no mailbox exists (shouldn't happen in normal flow)
      {:ok, push_navigate(socket, to: ~p"/email/inbox")}
    end
  end

  @impl true
  def handle_event("archive", %{"id" => message_id}, socket) do
    message = Email.get_message(message_id, socket.assigns.mailbox.id)

    case Email.archive_message(message) do
      {:ok, updated_message} ->
        # Remove from feed stream
        socket = stream_delete(socket, :messages, updated_message)

        {:noreply,
         socket
         |> put_flash(:info, "Message archived")
         |> assign(
           :messages,
           Enum.reject(socket.assigns.messages, &(&1.id == updated_message.id))
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to archive message")}
    end
  end

  @impl true
  def handle_event("move_to_inbox", %{"id" => message_id}, socket) do
    message = Email.get_message(message_id, socket.assigns.mailbox.id)

    case Email.update_message(message, %{category: "inbox"}) do
      {:ok, updated_message} ->
        # Remove from feed stream
        socket = stream_delete(socket, :messages, updated_message)

        {:noreply,
         socket
         |> put_flash(:info, "Message moved to inbox")
         |> assign(
           :messages,
           Enum.reject(socket.assigns.messages, &(&1.id == updated_message.id))
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to move message")}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    messages = Email.list_feed_messages(socket.assigns.mailbox.id)

    socket =
      socket
      |> assign(:messages, messages)
      |> stream(:messages, messages, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_email, message}, socket) do
    # Only add to feed if it's categorized as feed
    if message.category == "feed" and message.mailbox_id == socket.assigns.mailbox.id do
      socket =
        socket
        |> assign(:messages, [message | socket.assigns.messages])
        |> stream_insert(:messages, message, at: 0)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Helper functions specific to Feed
  defp message_type_badge(message) do
    cond do
      message.is_newsletter -> "NEWSLETTER"
      message.is_notification -> "NOTIFICATION"
      true -> "FEED"
    end
  end

  defp message_type_color(message) do
    cond do
      message.is_newsletter -> "badge-info"
      message.is_notification -> "badge-warning"
      true -> "badge-primary"
    end
  end
end
