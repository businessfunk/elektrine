defmodule ElektrineWeb.EmailLive.Sent do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers

  alias Elektrine.Email

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    unread_count = Email.unread_count(mailbox.id)
    
    # Get paginated messages
    page = 1
    pagination = Email.list_sent_messages_paginated(mailbox.id, page, 20)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, "Sent Messages")
     |> assign(:mailbox, mailbox)
     |> assign(:messages, pagination.messages)
     |> assign(:pagination, pagination)
     |> assign(:unread_count, unread_count)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    mailbox = socket.assigns.mailbox
    pagination = Email.list_sent_messages_paginated(mailbox.id, page, 20)
    
    socket =
      socket
      |> assign(:messages, pagination.messages)
      |> assign(:pagination, pagination)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    message = Email.get_message(id)
    
    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.delete_message(message)
      
      # Get updated pagination
      page = socket.assigns.pagination.page
      pagination = Email.list_sent_messages_paginated(socket.assigns.mailbox.id, page, 20)
      
      {:noreply,
       socket
       |> put_flash(:info, "Message deleted successfully")
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Message not found")}
    end
  end

  @impl true
  def handle_info({:new_email, _message}, socket) do
    mailbox = socket.assigns.mailbox

    # Update unread count in real-time
    unread_count = Email.unread_count(mailbox.id)

    {:noreply,
     socket
     |> assign(:unread_count, unread_count)}
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