defmodule ElektrineWeb.EmailLive.Inbox do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers

  alias Elektrine.Email
  alias Elektrine.Email.Message

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    
    # Get paginated messages
    page = 1
    pagination = Email.list_messages_paginated(mailbox.id, page, 20)

    # Subscribe to the PubSub topic only when the socket is connected
    if connected?(socket) do
      require Logger
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
      Logger.info("LiveView subscribed to PubSub topic: user:#{user.id}")

      # Real-time updates handled via PubSub - no polling needed
    end

    socket =
      socket
      |> stream_configure(:messages, dom_id: &"message-#{&1.id}")
      |> stream(:messages, pagination.messages)
      |> assign(:page_title, "Inbox")
      |> assign(:mailbox, mailbox)
      |> assign(:messages, pagination.messages)  # Keep for backward compatibility
      |> assign(:pagination, pagination)
      |> assign(:unread_count, Email.unread_count(mailbox.id))

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    mailbox = socket.assigns.mailbox
    pagination = Email.list_messages_paginated(mailbox.id, page, 20)
    
    socket =
      socket
      |> assign(:messages, pagination.messages)
      |> assign(:pagination, pagination)
      |> stream(:messages, pagination.messages, reset: true)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    page = socket.assigns.pagination.page
    pagination = Email.list_messages_paginated(socket.assigns.mailbox.id, page, 20)
    unread_count = Email.unread_count(socket.assigns.mailbox.id)

    {:noreply,
     socket
     |> assign(:messages, pagination.messages)
     |> assign(:pagination, pagination)
     |> assign(:unread_count, unread_count)
     |> stream(:messages, pagination.messages, reset: true)
     |> put_flash(:info, "Inbox refreshed")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    require Logger
    message = Email.get_message(id)

    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.delete_message(message)

      # Get updated pagination
      page = socket.assigns.pagination.page
      pagination = Email.list_messages_paginated(socket.assigns.mailbox.id, page, 20)

      Logger.info("Deleted message #{id}, updating stream")

      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)
       |> put_flash(:info, "Message deleted successfully")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Message not found")}
    end
  end

  @impl true
  def handle_info({:new_email, message}, socket) do
    require Logger
    mailbox = socket.assigns.mailbox

    # Log when we receive a message to help debugging
    Logger.info("Inbox LiveView received new_email event for mailbox #{mailbox.id}")
    Logger.info("Message type: #{if is_struct(message), do: inspect(message.__struct__), else: "plain map"}")
    Logger.info("Message keys: #{inspect(if is_map(message), do: Map.keys(message), else: "not a map")}")
    Logger.debug("Full message details: #{inspect(message, pretty: true)}")

    # Get the latest messages with pagination - stay on page 1 for new messages
    pagination = Email.list_messages_paginated(mailbox.id, 1, 20)
    unread_count = Email.unread_count(mailbox.id)
    
    Logger.info("Retrieved #{length(pagination.messages)} messages from database")
    Logger.info("Current messages in socket: #{length(socket.assigns.messages)}")

    # For logging purposes, try to find the new message in the latest batch
    db_message =
      if is_map(message) and Map.has_key?(message, :message_id) and not is_nil(message.message_id) do
        # Try to find by message_id first
        Enum.find(pagination.messages, fn m -> m.message_id == message.message_id end)
      else
        # Otherwise just use the most recent message
        List.first(pagination.messages)
      end

    if db_message do
      Logger.info("Found new message #{db_message.id} in database")
    else
      Logger.warn("Could not find new message in database, using raw message data")
    end

    # Always do a full refresh of the message list for reliability
    # This ensures the view is always up-to-date with the database
    Logger.info("Performing full refresh of inbox messages")

    # Force a unique key to ensure DOM updates
    socket =
      socket
      |> assign(:unread_count, unread_count)
      |> assign(:messages, pagination.messages)
      |> assign(:pagination, pagination)
      |> stream(:messages, pagination.messages, reset: true)
      |> push_event("inbox-updated", %{count: length(pagination.messages)})

    Logger.info("Socket updated with #{length(pagination.messages)} messages")
    Logger.info("Stream should be reset with new messages")
    Logger.info("Pushed inbox-updated event to client")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:unread_count_updated, new_count}, socket) do
    require Logger
    Logger.info("Inbox received unread count update: #{new_count}")
    
    {:noreply, assign(socket, :unread_count, new_count)}
  end

  defp get_or_create_mailbox(user) do
    case Email.get_user_mailbox(user.id) do
      nil -> 
        {:ok, mailbox} = Email.ensure_user_has_mailbox(user)
        mailbox
      mailbox -> mailbox
    end
  end

end