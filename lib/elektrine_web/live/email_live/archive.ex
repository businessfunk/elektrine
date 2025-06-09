defmodule ElektrineWeb.EmailLive.Archive do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers

  alias Elektrine.Email

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    
    # Get paginated archived messages
    page = 1
    pagination = Email.list_archived_messages_paginated(mailbox.id, page, 20)

    # Subscribe to the PubSub topic only when the socket is connected
    if connected?(socket) do
      require Logger
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
      Logger.info("Archive LiveView subscribed to PubSub topic: user:#{user.id}")
    end

    socket =
      socket
      |> stream_configure(:messages, dom_id: &"message-#{&1.id}")
      |> stream(:messages, pagination.messages)
      |> assign(:page_title, "Archive")
      |> assign(:mailbox, mailbox)
      |> assign(:messages, pagination.messages)
      |> assign(:pagination, pagination)
      |> assign(:unread_count, Email.unread_count(mailbox.id))

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    mailbox = socket.assigns.mailbox
    pagination = Email.list_archived_messages_paginated(mailbox.id, page, 20)
    
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
    pagination = Email.list_archived_messages_paginated(socket.assigns.mailbox.id, page, 20)
    unread_count = Email.unread_count(socket.assigns.mailbox.id)

    {:noreply,
     socket
     |> assign(:messages, pagination.messages)
     |> assign(:pagination, pagination)
     |> assign(:unread_count, unread_count)
     |> stream(:messages, pagination.messages, reset: true)
     |> put_flash(:info, "Archive refreshed")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    require Logger
    message = Email.get_message(id)

    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.delete_message(message)

      # Get updated pagination
      page = socket.assigns.pagination.page
      pagination = Email.list_archived_messages_paginated(socket.assigns.mailbox.id, page, 20)

      Logger.info("Deleted archived message #{id}, updating stream")

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
  def handle_event("unarchive", %{"id" => id}, socket) do
    message = Email.get_message(id)

    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.unarchive_message(message)

      # Get updated pagination
      page = socket.assigns.pagination.page
      pagination = Email.list_archived_messages_paginated(socket.assigns.mailbox.id, page, 20)

      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)
       |> put_flash(:info, "Message moved to inbox")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Message not found")}
    end
  end

  @impl true
  def handle_info({:new_email, _message}, socket) do
    # Refresh the archive when new emails arrive
    page = socket.assigns.pagination.page
    pagination = Email.list_archived_messages_paginated(socket.assigns.mailbox.id, page, 20)
    unread_count = Email.unread_count(socket.assigns.mailbox.id)

    socket =
      socket
      |> assign(:unread_count, unread_count)
      |> assign(:messages, pagination.messages)
      |> assign(:pagination, pagination)
      |> stream(:messages, pagination.messages, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:unread_count_updated, new_count}, socket) do
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