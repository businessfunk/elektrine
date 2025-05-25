defmodule ElektrineWeb.EmailLive.Inbox do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers

  alias Elektrine.Email
  alias Elektrine.Email.Message

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    messages = list_messages(mailbox.id)

    # Subscribe to the PubSub topic only when the socket is connected
    if connected?(socket) do
      require Logger
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
      Logger.info("LiveView subscribed to PubSub topic: user:#{user.id}")

          # Set up more frequent polling for real-time updates
      # 1 second poll interval for more immediate updates
      :timer.send_interval(1000, self(), :poll_for_messages)
      # Also do an immediate poll after short delay to catch any messages that arrived during page load
      Process.send_after(self(), :poll_for_messages, 500)
      Logger.info("Set up aggressive polling for real-time inbox updates")
    end

    socket =
      socket
      |> stream_configure(:messages, dom_id: &"message-#{&1.id}")
      |> stream(:messages, messages)
      |> assign(:page_title, "Inbox")
      |> assign(:mailbox, mailbox)
      |> assign(:messages, messages)  # Keep for backward compatibility
      |> assign(:unread_count, Email.unread_count(mailbox.id))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    require Logger
    message = Email.get_message(id)

    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.delete_message(message)

      # Get updated message list
      messages = list_messages(socket.assigns.mailbox.id)

      Logger.info("Deleted message #{id}, updating stream")

      {:noreply,
       socket
       |> stream_delete(:messages, message)
       |> assign(:messages, messages)  # Keep for backward compatibility
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
    Logger.debug("Message details: #{inspect(message)}")

    # Get the latest messages directly - more reliable for real-time updates
    latest_messages = list_messages(mailbox.id)
    unread_count = Email.unread_count(mailbox.id)

    # For logging purposes, try to find the new message in the latest batch
    db_message =
      if is_map(message) and Map.has_key?(message, :message_id) and not is_nil(message.message_id) do
        # Try to find by message_id first
        Enum.find(latest_messages, fn m -> m.message_id == message.message_id end)
      else
        # Otherwise just use the most recent message
        List.first(latest_messages)
      end

    if db_message do
      Logger.info("Found new message #{db_message.id} in database")
    else
      Logger.warn("Could not find new message in database, using raw message data")
    end

    # Always do a full refresh of the message list for reliability
    # This ensures the view is always up-to-date with the database
    Logger.info("Performing full refresh of inbox messages")

    socket =
      socket
      |> assign(:unread_count, unread_count)
      |> assign(:messages, latest_messages)
      |> stream(:messages, latest_messages, reset: true)

    # Process.send_after makes sure we get another update shortly after this one
    # in case the first one didn't capture all messages
    Process.send_after(self(), :poll_for_messages, 1000)

    {:noreply, socket}
  end

  defp get_or_create_mailbox(user) do
    case Email.get_user_mailbox(user.id) do
      nil -> 
        {:ok, mailbox} = Email.ensure_user_has_mailbox(user)
        mailbox
      mailbox -> mailbox
    end
  end

  defp list_messages(mailbox_id) do
    Email.list_messages(mailbox_id, 50)
  end

  @impl true
  def handle_info(:poll_for_messages, socket) do
    require Logger
    mailbox = socket.assigns.mailbox

    # Get latest messages and check if there are any changes
    latest_messages = list_messages(mailbox.id)
    current_messages = socket.assigns.messages
    # Get latest unread count
    unread_count = Email.unread_count(mailbox.id)

    # Check if there's any reason to refresh
    latest_ids = MapSet.new(latest_messages, & &1.id)
    current_ids = MapSet.new(current_messages, & &1.id)

    should_refresh =
      length(latest_messages) != length(current_messages) ||
      MapSet.size(latest_ids) != MapSet.size(current_ids) ||
      MapSet.difference(latest_ids, current_ids) |> MapSet.size() > 0 ||
      socket.assigns.unread_count != unread_count

    if should_refresh do
      Logger.info("Poll detected changes, refreshing inbox")

      socket =
        socket
        |> assign(:messages, latest_messages)
        |> assign(:unread_count, unread_count)
        |> stream(:messages, latest_messages, reset: true)

      {:noreply, socket}
    else
      # No significant changes detected
      {:noreply, socket}
    end
  end
end