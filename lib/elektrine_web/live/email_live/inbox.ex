defmodule ElektrineWeb.EmailLive.Inbox do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers
  import Phoenix.HTML, only: [raw: 1]

  alias Elektrine.Email

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)

    # Get filter and page from params
    filter = params["filter"] || "inbox"

    # Subscribe to the PubSub topic only when the socket is connected
    if connected?(socket) do
      require Logger
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
      Logger.info("LiveView subscribed to PubSub topic: user:#{user.id}")

      # Real-time updates handled via PubSub - no polling needed
    end

    socket =
      if filter == "aliases" do
        # For aliases tab, load aliases instead of messages
        aliases = Email.list_aliases(user.id)
        alias_changeset = Email.change_alias(%Email.Alias{})
        mailbox_changeset = Email.change_mailbox_forwarding(mailbox)

        socket
        |> assign(:page_title, "Email Aliases")
        |> assign(:mailbox, mailbox)
        |> assign(:aliases, aliases)
        |> assign(:alias_form, to_form(alias_changeset))
        |> assign(:mailbox_form, to_form(mailbox_changeset))
        |> assign(:current_filter, filter)
        |> assign(:unread_count, Email.unread_count(mailbox.id))
        |> assign(:new_contacts_count, get_new_contacts_count(mailbox.id))
        |> assign(:bulk_mail_count, get_bulk_mail_count(mailbox.id))
        |> assign(:show_reply_later_modal, false)
        |> assign(:reply_later_message, nil)
        |> assign(:selected_messages, MapSet.new())
        |> assign(:select_all_pages, false)
      else
        # For regular email tabs, load messages
        page = String.to_integer(params["page"] || "1")
        pagination = get_filtered_messages(mailbox.id, filter, page, 20)

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
        |> assign(:selected_messages, MapSet.new())
        |> assign(:select_all_pages, false)
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filter = params["filter"] || "inbox"
    user = socket.assigns.current_user

    socket =
      if filter == "aliases" do
        # For aliases tab, load aliases instead of messages
        aliases = Email.list_aliases(user.id)
        alias_changeset = Email.change_alias(%Email.Alias{})
        mailbox = Email.get_user_mailbox(user.id)
        mailbox_changeset = Email.change_mailbox_forwarding(mailbox)

        socket
        |> assign(:page_title, "Email Aliases")
        |> assign(:aliases, aliases)
        |> assign(:alias_form, to_form(alias_changeset))
        |> assign(:mailbox_form, to_form(mailbox_changeset))
        |> assign(:current_filter, filter)
      else
        # For regular email tabs, load messages
        page = String.to_integer(params["page"] || "1")
        mailbox = socket.assigns.mailbox
        pagination = get_filtered_messages(mailbox.id, filter, page, 20)

        socket
        |> assign(:messages, pagination.messages)
        |> assign(:pagination, pagination)
        |> assign(:current_filter, filter)
        |> assign(:page_title, get_page_title(filter))
        |> assign(:new_contacts_count, get_new_contacts_count(mailbox.id))
        |> assign(:bulk_mail_count, get_bulk_mail_count(mailbox.id))
        |> assign(:selected_messages, if(filter in ["inbox", "new_contacts"], do: socket.assigns[:selected_messages] || MapSet.new(), else: MapSet.new()))
        |> assign(:select_all_pages, if(filter in ["inbox", "new_contacts"], do: socket.assigns[:select_all_pages] || false, else: false))
        |> stream(:messages, pagination.messages, reset: true)
      end

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
  def handle_event("quick_action", %{"action" => action, "message_id" => message_id}, socket) do
    message = Email.get_message(message_id)

    if message && message.mailbox_id == socket.assigns.mailbox.id do
      case action do
        "archive" ->
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

        "reply" ->
          {:noreply, push_navigate(socket, to: ~p"/email/compose?reply=#{message.id}")}

        "forward" ->
          {:noreply, push_navigate(socket, to: ~p"/email/compose?forward=#{message.id}")}

        "mark_spam" ->
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

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "Message not found")}
    end
  end


  @impl true
  def handle_event("toggle_message_selection", %{"message_id" => message_id}, socket) do
    selected = socket.assigns.selected_messages
    message_id = String.to_integer(message_id)

    new_selected =
      if MapSet.member?(selected, message_id) do
        MapSet.delete(selected, message_id)
      else
        MapSet.put(selected, message_id)
      end

    # Reset select_all_pages if we're manually toggling messages
    {:noreply, 
     socket
     |> assign(:selected_messages, new_selected)
     |> assign(:select_all_pages, false)
     |> push_event("update_checkboxes", %{selected_ids: MapSet.to_list(new_selected), select_all: false})}
  end

  @impl true
  def handle_event("select_all_messages", _params, socket) do
    # Get all message IDs from the current page
    # We use the messages from assigns which contains the current page messages
    all_message_ids =
      socket.assigns.messages
      |> Enum.map(& &1.id)
      |> MapSet.new()

    {:noreply, 
     socket
     |> assign(:selected_messages, all_message_ids)
     |> push_event("update_checkboxes", %{selected_ids: MapSet.to_list(all_message_ids), select_all: true})}
  end

  @impl true
  def handle_event("deselect_all_messages", _params, socket) do
    {:noreply, 
     socket
     |> assign(:selected_messages, MapSet.new())
     |> assign(:select_all_pages, false)
     |> push_event("update_checkboxes", %{selected_ids: [], select_all: false})}
  end

  @impl true
  def handle_event("select_all_pages", _params, socket) do
    {:noreply, assign(socket, :select_all_pages, true)}
  end

  @impl true
  def handle_event("toggle_message_selection_on_shift", %{"message_id" => _message_id}, socket) do
    # This will be handled by JavaScript to check for shift key
    # If no shift key, just navigate normally
    {:noreply, socket}
  end

  @impl true
  def handle_event("bulk_action", %{"action" => action}, socket) do
    # Handle select all pages differently
    if socket.assigns.select_all_pages do
      handle_bulk_action_all_pages(socket, action)
    else
      selected_ids = MapSet.to_list(socket.assigns.selected_messages)

      if Enum.empty?(selected_ids) do
        {:noreply, put_flash(socket, :error, "No messages selected")}
      else
        case action do
          "archive" ->
            bulk_archive_messages(socket, selected_ids)

          "delete" ->
            bulk_delete_messages(socket, selected_ids)

          "mark_spam" ->
            bulk_mark_spam_messages(socket, selected_ids)

          "mark_read" ->
            bulk_mark_read_messages(socket, selected_ids)

          "mark_unread" ->
            bulk_mark_unread_messages(socket, selected_ids)

          _ ->
            {:noreply, put_flash(socket, :error, "Invalid action")}
        end
      end
    end
  end

  # Additional event handlers

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

  def handle_event("schedule_reply_later", %{"id" => id, "days" => days}, socket) do
    message = Email.get_message(id)

    if message && message.mailbox_id == socket.assigns.mailbox.id do
      days_int = String.to_integer(days)

      reply_at =
        DateTime.utc_now()
        |> DateTime.add(days_int * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

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

  def handle_event("close_reply_later_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_reply_later_modal, false)
     |> assign(:reply_later_message, nil)}
  end

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

  # Alias management events
  def handle_event("create_alias", %{"alias" => alias_params}, socket) do
    user = socket.assigns.current_user
    alias_params = Map.put(alias_params, "user_id", user.id)

    case Email.create_alias(alias_params) do
      {:ok, _alias} ->
        aliases = Email.list_aliases(user.id)
        alias_changeset = Email.change_alias(%Email.Alias{})

        {:noreply,
         socket
         |> assign(:aliases, aliases)
         |> assign(:alias_form, to_form(alias_changeset))
         |> put_flash(:info, "Email alias created successfully")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:alias_form, to_form(changeset))
         |> put_flash(:error, "Failed to create alias")}
    end
  end

  def handle_event("toggle_alias", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Email.get_alias(id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Alias not found")}

      alias ->
        case Email.update_alias(alias, %{enabled: !alias.enabled}) do
          {:ok, _alias} ->
            aliases = Email.list_aliases(user.id)
            status = if alias.enabled, do: "disabled", else: "enabled"

            {:noreply,
             socket
             |> assign(:aliases, aliases)
             |> put_flash(:info, "Alias #{status} successfully")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to update alias")}
        end
    end
  end

  def handle_event("delete_alias", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Email.get_alias(id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Alias not found")}

      alias ->
        case Email.delete_alias(alias) do
          {:ok, _alias} ->
            aliases = Email.list_aliases(user.id)

            {:noreply,
             socket
             |> assign(:aliases, aliases)
             |> put_flash(:info, "Alias deleted successfully")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to delete alias")}
        end
    end
  end

  def handle_event("edit_alias", %{"id" => _id}, socket) do
    # For now, just show a flash message - could implement inline editing later
    {:noreply, put_flash(socket, :info, "Edit functionality coming soon")}
  end

  def handle_event("update_mailbox_forwarding", %{"mailbox" => mailbox_params}, socket) do
    user = socket.assigns.current_user
    mailbox = Email.get_user_mailbox(user.id)

    case Email.update_mailbox_forwarding(mailbox, mailbox_params) do
      {:ok, updated_mailbox} ->
        mailbox_changeset = Email.change_mailbox_forwarding(updated_mailbox)

        {:noreply,
         socket
         |> assign(:mailbox, updated_mailbox)
         |> assign(:mailbox_form, to_form(mailbox_changeset))
         |> put_flash(:info, "Mailbox forwarding updated successfully")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:mailbox_form, to_form(changeset))
         |> put_flash(:error, "Failed to update mailbox forwarding")}
    end
  end

  @impl true
  def handle_info({:new_email, message}, socket) do
    require Logger
    mailbox = socket.assigns.mailbox

    # Log when we receive a message to help debugging
    Logger.info("Inbox LiveView received new_email event for mailbox #{mailbox.id}")

    Logger.info(
      "Message type: #{if is_struct(message), do: inspect(message.__struct__), else: "plain map"}"
    )

    Logger.info(
      "Message keys: #{inspect(if is_map(message), do: Map.keys(message), else: "not a map")}"
    )

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
      Logger.warning("Could not find new message in database, using raw message data")
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

  # Helper functions

  # Bulk operation helpers
  defp bulk_archive_messages(socket, message_ids) do
    messages = Enum.map(message_ids, &Email.get_message/1)
    valid_messages = Enum.filter(messages, &(&1 && &1.mailbox_id == socket.assigns.mailbox.id))

    Enum.each(valid_messages, &Email.archive_message/1)

    # Refresh the view
    refresh_messages_after_bulk_action(socket, length(valid_messages), "archived")
  end

  defp bulk_delete_messages(socket, message_ids) do
    messages = Enum.map(message_ids, &Email.get_message/1)
    valid_messages = Enum.filter(messages, &(&1 && &1.mailbox_id == socket.assigns.mailbox.id))

    Enum.each(valid_messages, &Email.delete_message/1)

    # Refresh the view
    refresh_messages_after_bulk_action(socket, length(valid_messages), "deleted")
  end

  defp bulk_mark_spam_messages(socket, message_ids) do
    messages = Enum.map(message_ids, &Email.get_message/1)
    valid_messages = Enum.filter(messages, &(&1 && &1.mailbox_id == socket.assigns.mailbox.id))

    Enum.each(valid_messages, &Email.mark_as_spam/1)

    # Refresh the view
    refresh_messages_after_bulk_action(socket, length(valid_messages), "marked as spam")
  end

  defp bulk_mark_read_messages(socket, message_ids) do
    messages = Enum.map(message_ids, &Email.get_message/1)
    valid_messages = Enum.filter(messages, &(&1 && &1.mailbox_id == socket.assigns.mailbox.id))

    Enum.each(valid_messages, &Email.mark_as_read/1)

    # Refresh the view without removing messages
    page = socket.assigns.pagination.page
    filter = socket.assigns.current_filter
    pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)
    unread_count = Email.unread_count(socket.assigns.mailbox.id)

    {:noreply,
     socket
     |> assign(:messages, pagination.messages)
     |> assign(:pagination, pagination)
     |> assign(:unread_count, unread_count)
     |> assign(:selected_messages, MapSet.new())
     |> assign(:select_all_pages, false)
     |> stream(:messages, pagination.messages, reset: true)
     |> put_flash(:info, "#{length(valid_messages)} messages marked as read")}
  end

  defp bulk_mark_unread_messages(socket, message_ids) do
    messages = Enum.map(message_ids, &Email.get_message/1)
    valid_messages = Enum.filter(messages, &(&1 && &1.mailbox_id == socket.assigns.mailbox.id))

    Enum.each(valid_messages, &Email.mark_as_unread/1)

    # Refresh the view without removing messages
    page = socket.assigns.pagination.page
    filter = socket.assigns.current_filter
    pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)
    unread_count = Email.unread_count(socket.assigns.mailbox.id)

    {:noreply,
     socket
     |> assign(:messages, pagination.messages)
     |> assign(:pagination, pagination)
     |> assign(:unread_count, unread_count)
     |> assign(:selected_messages, MapSet.new())
     |> assign(:select_all_pages, false)
     |> stream(:messages, pagination.messages, reset: true)
     |> put_flash(:info, "#{length(valid_messages)} messages marked as unread")}
  end

  defp refresh_messages_after_bulk_action(socket, count, action) do
    # Get updated pagination
    page = socket.assigns.pagination.page
    filter = socket.assigns.current_filter
    pagination = get_filtered_messages(socket.assigns.mailbox.id, filter, page, 20)
    unread_count = Email.unread_count(socket.assigns.mailbox.id)

    {:noreply,
     socket
     |> assign(:messages, pagination.messages)
     |> assign(:pagination, pagination)
     |> assign(:unread_count, unread_count)
     |> assign(:selected_messages, MapSet.new())
     |> assign(:select_all_pages, false)
     |> assign(:new_contacts_count, get_new_contacts_count(socket.assigns.mailbox.id))
     |> assign(:bulk_mail_count, get_bulk_mail_count(socket.assigns.mailbox.id))
     |> stream(:messages, pagination.messages, reset: true)
     |> put_flash(:info, "#{count} messages #{action}")}
  end

  defp handle_bulk_action_all_pages(socket, action) do
    mailbox_id = socket.assigns.mailbox.id
    filter = socket.assigns.current_filter
    
    # Get all message IDs for the current filter
    all_message_ids = get_all_message_ids_for_filter(mailbox_id, filter)
    
    case action do
      "delete" ->
        count = length(all_message_ids)
        messages = Enum.map(all_message_ids, &Email.get_message/1)
        valid_messages = Enum.filter(messages, &(&1 && &1.mailbox_id == socket.assigns.mailbox.id))
        Enum.each(valid_messages, &Email.delete_message/1)
        refresh_messages_after_bulk_action(socket, length(valid_messages), "deleted")
        
      "archive" ->
        count = length(all_message_ids)
        messages = Enum.map(all_message_ids, &Email.get_message/1)
        valid_messages = Enum.filter(messages, &(&1 && &1.mailbox_id == socket.assigns.mailbox.id))
        Enum.each(valid_messages, &Email.archive_message/1)
        refresh_messages_after_bulk_action(socket, length(valid_messages), "archived")
        
      "mark_spam" ->
        count = length(all_message_ids)
        messages = Enum.map(all_message_ids, &Email.get_message/1)
        valid_messages = Enum.filter(messages, &(&1 && &1.mailbox_id == socket.assigns.mailbox.id))
        Enum.each(valid_messages, &Email.mark_as_spam/1)
        refresh_messages_after_bulk_action(socket, length(valid_messages), "marked as spam")
        
      "mark_read" ->
        count = length(all_message_ids)
        messages = Enum.map(all_message_ids, &Email.get_message/1)
        valid_messages = Enum.filter(messages, &(&1 && &1.mailbox_id == socket.assigns.mailbox.id))
        Enum.each(valid_messages, &Email.mark_as_read/1)
        refresh_messages_after_bulk_action(socket, length(valid_messages), "marked as read")
        
      "mark_unread" ->
        count = length(all_message_ids)
        messages = Enum.map(all_message_ids, &Email.get_message/1)
        valid_messages = Enum.filter(messages, &(&1 && &1.mailbox_id == socket.assigns.mailbox.id))
        Enum.each(valid_messages, &Email.mark_as_unread/1)
        refresh_messages_after_bulk_action(socket, length(valid_messages), "marked as unread")
        
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid action")}
    end
  end

  defp get_all_message_ids_for_filter(mailbox_id, filter) do
    # Get all messages for the filter without pagination
    messages = case filter do
      "new_contacts" -> Email.list_all_screener_messages(mailbox_id)
      "bulk_mail" -> Email.list_all_feed_messages(mailbox_id)
      "paper_trail" -> Email.list_all_paper_trail_messages(mailbox_id)
      "the_pile" -> Email.list_all_set_aside_messages(mailbox_id)
      "boomerang" -> Email.list_all_reply_later_messages(mailbox_id)
      _ -> Email.list_all_inbox_messages(mailbox_id)
    end
    
    Enum.map(messages, & &1.id)
  end

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
      "aliases" -> "Email Aliases"
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

      mailbox ->
        mailbox
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
      "aliases" -> "hero-at-symbol"
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
      "aliases" -> "Manage your email aliases and forwarding rules"
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
      "aliases" -> "No email aliases"
      _ -> "Your inbox is empty"
    end
  end

  defp get_empty_description(filter) do
    case filter do
      "new_contacts" ->
        "No messages waiting for approval. New messages from unknown senders will appear here."

      "bulk_mail" ->
        "Newsletters, notifications, and automated messages will appear here when they arrive."

      "paper_trail" ->
        "Receipts, confirmations, and important records will be organized here."

      "the_pile" ->
        "Messages you save for later processing will appear here."

      "boomerang" ->
        "Messages you've scheduled to reply to later will appear here."

      "aliases" ->
        "Create email aliases to forward emails to different addresses."

      _ ->
        "No messages have arrived yet. When someone sends you an email, it will appear here."
    end
  end

  defp get_message_card_class(message, filter) do
    base_class =
      case filter do
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
    html =
      cond do
        filter == "new_contacts" ->
          ~s"""
          <div class="badge badge-warning badge-xs">NEW CONTACT</div>
          """

        filter == "bulk_mail" ->
          type_badge =
            cond do
              message.is_newsletter -> "NEWSLETTER"
              message.is_notification -> "NOTIFICATION"
              true -> "BULK"
            end

          color =
            cond do
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
          reply_date =
            if message.reply_later_at do
              Calendar.strftime(message.reply_later_at, "%b %d")
            else
              "SCHEDULED"
            end

          ~s"""
          <div class="badge badge-error badge-xs">#{reply_date}</div>
          """

        true ->
          # General badges for inbox
          unread_indicator =
            if not message.read do
              ~s[<div class="w-2 h-2 bg-primary rounded-full animate-pulse"></div>]
            else
              ""
            end

          spam_badge =
            if message.spam do
              ~s[<div class="badge badge-error badge-xs">SPAM</div>]
            else
              ""
            end

          archived_badge =
            if message.archived do
              ~s[<div class="badge badge-secondary badge-xs">ARCHIVED</div>]
            else
              ""
            end

          attachment_badge =
            if message.has_attachments do
              ~s[<div class="badge badge-info badge-xs" title="Has attachments"><svg class="w-3 h-3 inline" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M8 4a3 3 0 00-3 3v4a5 5 0 0010 0V7a1 1 0 112 0v4a7 7 0 11-14 0V7a5 5 0 1110 0v4a3 3 0 11-6 0V7a1 1 0 012 0v4a1 1 0 102 0V7a3 3 0 00-3-3z" clip-rule="evenodd"></path></svg></div>]
            else
              ""
            end

          unread_indicator <> spam_badge <> archived_badge <> attachment_badge
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
