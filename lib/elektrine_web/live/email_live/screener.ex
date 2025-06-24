defmodule ElektrineWeb.EmailLive.Screener do
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
      # Get pending messages
      messages = Email.list_screener_messages(mailbox.id)

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
  def handle_event("approve", %{"id" => message_id}, socket) do
    message = Email.get_message(message_id, socket.assigns.mailbox.id)

    case Email.approve_sender(message) do
      {:ok, updated_message} ->
        # Remove from screener stream
        socket = stream_delete(socket, :messages, updated_message)

        {:noreply,
         socket
         |> put_flash(:info, "Sender approved and added to your contacts")
         |> assign(
           :messages,
           Enum.reject(socket.assigns.messages, &(&1.id == updated_message.id))
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve sender")}
    end
  end

  @impl true
  def handle_event("reject", %{"id" => message_id}, socket) do
    message = Email.get_message(message_id, socket.assigns.mailbox.id)

    case Email.reject_sender(message) do
      {:ok, updated_message} ->
        # Remove from screener stream
        socket = stream_delete(socket, :messages, updated_message)

        {:noreply,
         socket
         |> put_flash(:info, "Sender rejected")
         |> assign(
           :messages,
           Enum.reject(socket.assigns.messages, &(&1.id == updated_message.id))
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reject sender")}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    messages = Email.list_screener_messages(socket.assigns.mailbox.id)

    socket =
      socket
      |> assign(:messages, messages)
      |> stream(:messages, messages, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_email, message}, socket) do
    # Only add to screener if it's pending approval
    if message.screener_status == "pending" and message.mailbox_id == socket.assigns.mailbox.id do
      socket =
        socket
        |> assign(:messages, [message | socket.assigns.messages])
        |> stream_insert(:messages, message, at: 0)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end
end
