defmodule ElektrineWeb.TemporaryMailboxLive.Show do
  use ElektrineWeb, :live_view

  alias Elektrine.Email

  @impl true
  def mount(%{"token" => token}, session, socket) do
    # Get mailbox by token
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        # Invalid or expired token, redirect
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "Temporary mailbox not found or expired.")
          |> Phoenix.LiveView.push_navigate(to: ~p"/temp-mail")

        {:ok, socket}

      mailbox ->
        # Get messages for this mailbox using the adapter
        messages = Email.MailboxAdapter.list_messages(mailbox.id, :temporary, 50)

        # Check if this is the user's mailbox from session
        is_owner = Map.get(session, "temporary_mailbox_token") == token

        if connected?(socket) do
          # Subscribe to PubSub for real-time updates
          Phoenix.PubSub.subscribe(Elektrine.PubSub, "mailbox:#{mailbox.id}")

          # Set up polling for expiration countdown
          :timer.send_interval(60_000, self(), :update_remaining_time)

          # Set up polling for new messages
          :timer.send_interval(10_000, self(), :poll_for_messages)
          Process.send_after(self(), :poll_for_messages, 500)
        end

        # Preserve current_user if they're authenticated
        current_user = socket.assigns[:current_user]

        socket =
          socket
          |> assign(:current_user, current_user)
          |> assign(:mailbox, mailbox)
          |> assign(:messages, messages)
          |> assign(:is_owner, is_owner)
          |> assign(:expires_at, mailbox.expires_at)
          |> assign(:remaining_time, calculate_remaining_time(mailbox.expires_at))

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("delete_message", %{"id" => id}, socket) do
    # Verify ownership
    if socket.assigns.is_owner do
      mailbox = socket.assigns.mailbox
      message = Elektrine.Email.get_message(id)

      if message do
        {:ok, _} = Elektrine.Email.delete_message(message)

        # Get updated messages using the adapter
        messages = Email.MailboxAdapter.list_messages(mailbox.id, :temporary, 50)

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> Phoenix.LiveView.put_flash(:info, "Message deleted successfully.")}
      else
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Message not found.")}
      end
    else
      {:noreply,
       socket
       |> Phoenix.LiveView.put_flash(
         :error,
         "You don't have permission to delete messages from this mailbox."
       )}
    end
  end

  @impl true
  def handle_event("extend_mailbox", %{"hours" => hours_str}, socket) do
    # Verify ownership
    if socket.assigns.is_owner do
      mailbox = socket.assigns.mailbox
      hours = String.to_integer(hours_str)

      case Email.extend_temporary_mailbox(mailbox.id, hours) do
        {:ok, updated_mailbox} ->
          # Update socket with new expiration time
          {:noreply,
           socket
           |> assign(:mailbox, updated_mailbox)
           |> assign(:expires_at, updated_mailbox.expires_at)
           |> assign(:remaining_time, calculate_remaining_time(updated_mailbox.expires_at))
           |> Phoenix.LiveView.put_flash(:info, "Mailbox extended successfully.")}

        {:error, _} ->
          {:noreply,
           socket
           |> Phoenix.LiveView.put_flash(:error, "Failed to extend mailbox.")}
      end
    else
      {:noreply,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You don't have permission to extend this mailbox.")}
    end
  end

  @impl true
  def handle_event("extend_mailbox", _params, socket) do
    # Default to 24 hours if no hours specified
    handle_event("extend_mailbox", %{"hours" => "24"}, socket)
  end

  @impl true
  def handle_event("create_new_mailbox", _params, socket) do
    # Create a new temporary mailbox with domain awareness
    domain = get_request_domain_from_socket(socket)
    {:ok, mailbox} = Email.create_temporary_mailbox(24, domain)

    # We can't directly modify the session from LiveView
    # So we'll redirect through a controller action that can set the session
    {:noreply,
     socket
     |> Phoenix.LiveView.redirect(to: ~p"/temp-mail/#{mailbox.token}/set_token")}
  end

  @impl true
  def handle_event("copy_email", _params, socket) do
    # This is just for UI feedback, actual copying happens with JS
    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    # Just reload the current page with fresh data
    mailbox = socket.assigns.mailbox
    messages = Email.list_messages(mailbox.id, 50)

    {:noreply,
     socket
     |> assign(:messages, messages)}
  end

  @impl true
  def handle_info({:new_email, _message}, socket) do
    # Update messages using our adapter
    mailbox = socket.assigns.mailbox
    messages = Email.MailboxAdapter.list_messages(mailbox.id, :temporary, 50)

    {:noreply,
     socket
     |> assign(:messages, messages)}
  end

  @impl true
  def handle_info(:update_remaining_time, socket) do
    # Update the remaining time display
    {:noreply,
     socket
     |> assign(:remaining_time, calculate_remaining_time(socket.assigns.expires_at))}
  end

  @impl true
  def handle_info(:poll_for_messages, socket) do
    # Get latest messages using our adapter
    mailbox = socket.assigns.mailbox
    latest_messages = Email.MailboxAdapter.list_messages(mailbox.id, :temporary, 50)

    # Check if message count changed
    if length(latest_messages) != length(socket.assigns.messages) do
      {:noreply,
       socket
       |> assign(:messages, latest_messages)}
    else
      {:noreply, socket}
    end
  end

  # Helper to calculate remaining time until expiration
  defp calculate_remaining_time(expires_at) do
    now = DateTime.utc_now()

    case DateTime.compare(expires_at, now) do
      :gt ->
        # Calculate difference
        diff_seconds = DateTime.diff(expires_at, now, :second)
        days = div(diff_seconds, 86400)
        hours = div(rem(diff_seconds, 86400), 3600)
        minutes = div(rem(diff_seconds, 3600), 60)

        cond do
          days > 0 -> "#{days} days and #{hours} hours"
          hours > 0 -> "#{hours} hours and #{minutes} minutes"
          true -> "#{minutes} minutes"
        end

      _ ->
        "Expired"
    end
  end

  # Helper to extract domain from LiveView socket
  defp get_request_domain_from_socket(socket) do
    # Try to get host from connect_info if available, otherwise default
    host =
      if connected?(socket) do
        case get_connect_info(socket, :host) do
          # Remove port if present
          host when is_binary(host) -> String.split(host, ":") |> hd()
          _ -> nil
        end
      else
        # During initial mount, we don't have connect_info yet
        # We'll default to elektrine.com and let it be corrected later if needed
        nil
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
        # Default to elektrine.com for unknown hosts or when not connected
        "elektrine.com"
    end
  end
end
