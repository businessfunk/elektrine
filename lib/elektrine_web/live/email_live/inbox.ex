defmodule ElektrineWeb.EmailLive.Inbox do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers
  import Phoenix.HTML, only: [raw: 1]

  alias Elektrine.Email
  alias Elektrine.Email.Message

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    
    # Get filter and page from params
    filter = params["filter"] || "inbox"
    page = String.to_integer(params["page"] || "1")
    pagination = get_filtered_messages(mailbox.id, filter, page, 20)

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
      |> assign(:page_title, get_page_title(filter))
      |> assign(:mailbox, mailbox)
      |> assign(:messages, pagination.messages)
      |> assign(:pagination, pagination)
      |> assign(:current_filter, filter)
      |> assign(:unread_count, Email.unread_count(mailbox.id))
      |> assign(:new_contacts_count, get_new_contacts_count(mailbox.id))
      |> assign(:bulk_mail_count, get_bulk_mail_count(mailbox.id))
      |> assign(:show_reply_later_modal, false)
      |> assign(:reply_later_message, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    filter = params["filter"] || "inbox"
    mailbox = socket.assigns.mailbox
    pagination = get_filtered_messages(mailbox.id, filter, page, 20)
    
    socket =
      socket
      |> assign(:messages, pagination.messages)
      |> assign(:pagination, pagination)
      |> assign(:current_filter, filter)
      |> assign(:page_title, get_page_title(filter))
      |> assign(:new_contacts_count, get_new_contacts_count(mailbox.id))
      |> assign(:bulk_mail_count, get_bulk_mail_count(mailbox.id))
      |> stream(:messages, pagination.messages, reset: true)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    page = socket.assigns.pagination.page
    filter = socket.assigns.current_filter
    pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)
    unread_count = Email.unread_count(socket.assigns.mailbox.id)

    {:noreply,
     socket
     |> assign(:messages, pagination.messages)
     |> assign(:pagination, pagination)
     |> assign(:unread_count, unread_count)
     |> assign(:new_contacts_count, get_new_contacts_count(socket.assigns.mailbox.id))
     |> assign(:bulk_mail_count, get_bulk_mail_count(socket.assigns.mailbox.id))
     |> stream(:messages, pagination.messages, reset: true)
     |> put_flash(:info, "Messages refreshed")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    require Logger
    message = Email.get_message(id)

    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.delete_message(message)

      # Get updated pagination
      page = socket.assigns.pagination.page
      filter = socket.assigns.current_filter
      pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)

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
  def handle_event("mark_spam", %{"id" => id}, socket) do
    message = Email.get_message(id)

    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.mark_as_spam(message)

      # Get updated pagination
      page = socket.assigns.pagination.page
      filter = socket.assigns.current_filter
      pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)

      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)
       |> put_flash(:info, "Message marked as spam")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Message not found")}
    end
  end

  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    message = Email.get_message(id)

    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.archive_message(message)

      # Get updated pagination
      page = socket.assigns.pagination.page
      filter = socket.assigns.current_filter
      pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)

      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)
       |> put_flash(:info, "Message archived")}
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
    filter = socket.assigns.current_filter
    pagination = get_filtered_messages(mailbox.id, filter, 1, 20)
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

  # Hey.com event handlers
  
  @impl true
  def handle_event("approve_sender", %{"id" => id}, socket) do
    message = Email.get_message(id)
    
    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.approve_sender(message)
      
      # Refresh current view
      page = socket.assigns.pagination.page
      filter = socket.assigns.current_filter
      pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)
      
      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)
       |> assign(:new_contacts_count, get_new_contacts_count(socket.assigns.mailbox.id))
       |> put_flash(:info, "Sender approved and added to contacts")}
    else
      {:noreply, put_flash(socket, :error, "Message not found")}
    end
  end
  
  @impl true
  def handle_event("reject_sender", %{"id" => id}, socket) do
    message = Email.get_message(id)
    
    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.reject_sender(message)
      
      # Refresh current view
      page = socket.assigns.pagination.page
      filter = socket.assigns.current_filter
      pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)
      
      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)
       |> assign(:new_contacts_count, get_new_contacts_count(socket.assigns.mailbox.id))
       |> put_flash(:info, "Sender rejected")}
    else
      {:noreply, put_flash(socket, :error, "Message not found")}
    end
  end
  
  @impl true
  def handle_event("save_message", %{"id" => id}, socket) do
    message = Email.get_message(id)
    
    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.set_aside_message(message)
      
      # Refresh current view
      page = socket.assigns.pagination.page
      filter = socket.assigns.current_filter
      pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)
      
      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)
       |> put_flash(:info, "Message saved")}
    else
      {:noreply, put_flash(socket, :error, "Message not found")}
    end
  end
  
  @impl true
  def handle_event("show_reply_later_modal", %{"id" => id}, socket) do
    message = Email.get_message(id)
    
    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:noreply,
       socket
       |> assign(:reply_later_message, message)
       |> assign(:show_reply_later_modal, true)}
    else
      {:noreply, put_flash(socket, :error, "Message not found")}
    end
  end

  @impl true
  def handle_event("schedule_reply_later", %{"id" => id, "days" => days}, socket) do
    message = Email.get_message(id)
    
    if message && message.mailbox_id == socket.assigns.mailbox.id do
      days_int = String.to_integer(days)
      reply_at = DateTime.utc_now() |> DateTime.add(days_int * 24 * 60 * 60, :second) |> DateTime.truncate(:second)
      
      {:ok, _} = Email.reply_later_message(message, reply_at)
      
      # Refresh current view
      page = socket.assigns.pagination.page
      filter = socket.assigns.current_filter
      pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)
      
      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)
       |> assign(:show_reply_later_modal, false)
       |> assign(:reply_later_message, nil)
       |> put_flash(:info, "Message scheduled for reply in #{days_int} day(s)")}
    else
      {:noreply, put_flash(socket, :error, "Message not found")}
    end
  end

  @impl true
  def handle_event("close_reply_later_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_reply_later_modal, false)
     |> assign(:reply_later_message, nil)}
  end

  @impl true
  def handle_event("clear_reply_later", %{"id" => id}, socket) do
    message = Email.get_message(id)
    
    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.clear_reply_later(message)
      
      # Refresh current view
      page = socket.assigns.pagination.page
      filter = socket.assigns.current_filter
      pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)
      
      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)
       |> put_flash(:info, "Reply later cleared - message moved back to inbox")}
    else
      {:noreply, put_flash(socket, :error, "Message not found")}
    end
  end

  @impl true
  def handle_event("move_to_inbox", %{"id" => id}, socket) do
    message = Email.get_message(id)
    
    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.update_message(message, %{category: "inbox"})
      
      # Refresh current view
      page = socket.assigns.pagination.page
      filter = socket.assigns.current_filter
      pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)
      
      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, pagination.messages)
       |> assign(:pagination, pagination)
       |> assign(:bulk_mail_count, get_bulk_mail_count(socket.assigns.mailbox.id))
       |> put_flash(:info, "Message moved to inbox")}
    else
      {:noreply, put_flash(socket, :error, "Message not found")}
    end
  end
  
  # Helper functions
  
  defp get_filtered_messages(mailbox_id, filter, page, per_page) do
    case filter do
      "new_contacts" -> Email.list_screener_messages_paginated(mailbox_id, page, per_page)
      "bulk_mail" -> Email.list_feed_messages_paginated(mailbox_id, page, per_page) 
      "paper_trail" -> Email.list_paper_trail_messages_paginated(mailbox_id, page, per_page)
      "the_pile" -> Email.list_set_aside_messages_paginated(mailbox_id, page, per_page)
      "boomerang" -> Email.list_reply_later_messages_paginated(mailbox_id, page, per_page)
      _ -> Email.list_inbox_messages_paginated(mailbox_id, page, per_page)
    end
  end
  
  defp get_page_title(filter) do
    case filter do
      "new_contacts" -> "New Contacts"
      "bulk_mail" -> "Bulk Mail"
      "paper_trail" -> "Paper Trail"
      "the_pile" -> "The Pile"
      "boomerang" -> "Boomerang"
      _ -> "Inbox"
    end
  end
  
  defp get_new_contacts_count(mailbox_id) do
    Email.list_screener_messages(mailbox_id) |> length()
  end
  
  defp get_bulk_mail_count(mailbox_id) do
    Email.list_feed_messages(mailbox_id) |> length()
  end
  
  defp get_or_create_mailbox(user) do
    case Email.get_user_mailbox(user.id) do
      nil -> 
        {:ok, mailbox} = Email.ensure_user_has_mailbox(user)
        mailbox
      mailbox -> mailbox
    end
  end
  
  # Template helper functions
  
  defp get_filter_icon(filter) do
    case filter do
      "new_contacts" -> "hero-user-plus"
      "bulk_mail" -> "hero-inbox-stack"
      "paper_trail" -> "hero-document-text"
      "the_pile" -> "hero-archive-box"
      "boomerang" -> "hero-arrow-uturn-left"
      _ -> "hero-inbox"
    end
  end
  
  defp get_filter_description(filter) do
    case filter do
      "new_contacts" -> "Messages from first-time senders awaiting approval"
      "bulk_mail" -> "Newsletters, notifications, and automated messages"
      "paper_trail" -> "Receipts, confirmations, and important records"
      "the_pile" -> "Messages you've saved for later processing"
      "boomerang" -> "Messages that need replies by a certain time"
      _ -> "Your main email inbox"
    end
  end
  
  defp get_empty_title(filter) do
    case filter do
      "new_contacts" -> "All clear!"
      "bulk_mail" -> "No bulk mail"
      "paper_trail" -> "No paper trail"
      "the_pile" -> "The pile is empty"
      "boomerang" -> "Nothing scheduled"
      _ -> "Your inbox is empty"
    end
  end
  
  defp get_empty_description(filter) do
    case filter do
      "new_contacts" -> "No messages waiting for approval. New messages from unknown senders will appear here."
      "bulk_mail" -> "Newsletters, notifications, and automated messages will appear here when they arrive."
      "paper_trail" -> "Receipts, confirmations, and important records will be organized here."
      "the_pile" -> "Messages you save for later processing will appear here."
      "boomerang" -> "Messages you've scheduled to reply to later will appear here."
      _ -> "No messages have arrived yet. When someone sends you an email, it will appear here."
    end
  end
  
  defp get_message_card_class(message, filter) do
    base_class = case filter do
      "new_contacts" -> "bg-warning/5 border-warning/20"
      "bulk_mail" -> "bg-info/5 border-info/20"
      "paper_trail" -> "bg-accent/5 border-accent/20"
      "the_pile" -> "bg-secondary/5 border-secondary/20"
      "boomerang" -> "bg-error/5 border-error/20"
      _ -> if message.read, do: "bg-base-100", else: "bg-primary/5 border-primary/20"
    end
    
    base_class
  end
  
  defp render_message_badges(message, filter) do
    html = cond do
      filter == "new_contacts" ->
        ~s"""
        <div class="badge badge-warning badge-xs">NEW CONTACT</div>
        """
      filter == "bulk_mail" ->
        type_badge = cond do
          message.is_newsletter -> "NEWSLETTER"
          message.is_notification -> "NOTIFICATION"
          true -> "BULK"
        end
        color = cond do
          message.is_newsletter -> "badge-info"
          message.is_notification -> "badge-warning"
          true -> "badge-primary"
        end
        ~s"""
        <div class="badge badge-xs #{color}">#{type_badge}</div>
        """
      filter == "paper_trail" ->
        type_badge = if message.is_receipt, do: "RECEIPT", else: "RECORD"
        ~s"""
        <div class="badge badge-accent badge-xs">#{type_badge}</div>
        """
      filter == "the_pile" ->
        ~s"""
        <div class="badge badge-secondary badge-xs">SAVED</div>
        """
      filter == "boomerang" ->
        reply_date = if message.reply_later_at do
          Calendar.strftime(message.reply_later_at, "%b %d")
        else
          "SCHEDULED"
        end
        ~s"""
        <div class="badge badge-error badge-xs">#{reply_date}</div>
        """
      true ->
        # General badges for inbox
        unread_indicator = if not message.read do
          ~s[<div class="w-2 h-2 bg-primary rounded-full animate-pulse"></div>]
        else
          ""
        end
        
        spam_badge = if message.spam do
          ~s[<div class="badge badge-error badge-xs">SPAM</div>]
        else
          ""
        end
        
        archived_badge = if message.archived do
          ~s[<div class="badge badge-secondary badge-xs">ARCHIVED</div>]
        else
          ""
        end
        
        unread_indicator <> spam_badge <> archived_badge
    end
    
    raw(html)
  end
  
  defp render_action_menu(message, filter) do
    html = case filter do
      "bulk_mail" ->
        ~s"""
        <li>
          <button phx-click="move_to_inbox" phx-value-id="#{message.id}" class="text-sm">
            <svg class="h-4 w-4 inline mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2M4 13h2m0 0V9a2 2 0 012-2h8a2 2 0 012 2v4M6 13h8m0 0v5a2 2 0 01-2 2H8a2 2 0 01-2-2v-5z" />
            </svg>
            Move to Inbox
          </button>
        </li>
        <li>
          <button phx-click="archive" phx-value-id="#{message.id}" class="text-sm">
            <svg class="h-4 w-4 inline mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4" />
            </svg>
            Archive
          </button>
        </li>
        """
      "the_pile" ->
        ~s"""
        <li>
          <button phx-click="move_to_inbox" phx-value-id="#{message.id}" class="text-sm">
            <svg class="h-4 w-4 inline mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2M4 13h2m0 0V9a2 2 0 012-2h8a2 2 0 012 2v4M6 13h8m0 0v5a2 2 0 01-2 2H8a2 2 0 01-2-2v-5z" />
            </svg>
            Move to Inbox
          </button>
        </li>
        """
      "boomerang" ->
        ~s"""
        <li>
          <button phx-click="clear_reply_later" phx-value-id="#{message.id}" class="text-sm">
            <svg class="h-4 w-4 inline mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
            </svg>
            Mark as Replied
          </button>
        </li>
        <li>
          <button phx-click="show_reply_later_modal" phx-value-id="#{message.id}" class="text-sm">
            <svg class="h-4 w-4 inline mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            Reschedule
          </button>
        </li>
        """
      _ ->
        ~s"""
        <li>
          <button phx-click="save_message" phx-value-id="#{message.id}" class="text-sm">
            <svg class="h-4 w-4 inline mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
            </svg>
            Save Message
          </button>
        </li>
        <li>
          <button phx-click="show_reply_later_modal" phx-value-id="#{message.id}" class="text-sm">
            <svg class="h-4 w-4 inline mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            Reply Later
          </button>
        </li>
        <li>
          <button phx-click="archive" phx-value-id="#{message.id}" class="text-sm">
            <svg class="h-4 w-4 inline mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4" />
            </svg>
            Archive
          </button>
        </li>
        <li>
          <button phx-click="mark_spam" phx-value-id="#{message.id}" class="text-sm">
            <svg class="h-4 w-4 inline mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
            </svg>
            Mark Spam
          </button>
        </li>
        <li>
          <button phx-click="delete" phx-value-id="#{message.id}" class="text-sm text-error" data-confirm="Are you sure you want to delete this message?">
            <svg class="h-4 w-4 inline mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
            Delete
          </button>
        </li>
        """
    end
    
    raw(html)
  end
  
  defp get_pagination_url(filter, page) do
    if filter == "inbox" do
      ~p"/email/inbox?page=#{page}"
    else
      ~p"/email/inbox?filter=#{filter}&page=#{page}"
    end
  end

end