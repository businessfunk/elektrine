defmodule ElektrineWeb.TemporaryMailboxLive.Message do
  use ElektrineWeb, :live_view
  
  alias Elektrine.Email
  
  @impl true
  def mount(%{"token" => token, "id" => id}, session, socket) do
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
        # Get the specific message using the mailbox adapter
        case Elektrine.Email.get_message(id) do
          nil ->
            # Message not found
            socket =
              socket
              |> Phoenix.LiveView.put_flash(:error, "Message not found.")
              |> Phoenix.LiveView.push_navigate(to: ~p"/temp-mail/#{token}")
              
            {:ok, socket}
            
          message ->
            # Mark message as read
            unless message.read do
              {:ok, _updated_message} = Elektrine.Email.mark_as_read(message)
            end
            
            # Check if this is the user's mailbox from session
            is_owner = Map.get(session, "temporary_mailbox_token") == token
            
            if connected?(socket) do
              # Set up polling for expiration countdown
              :timer.send_interval(60_000, self(), :update_remaining_time)
            end
            
            # Preserve current_user if they're authenticated
            current_user = socket.assigns[:current_user]
            
            socket =
              socket
              |> assign(:current_user, current_user)
              |> assign(:mailbox, mailbox)
              |> assign(:message, message)
              |> assign(:is_owner, is_owner)
              |> assign(:remaining_time, calculate_remaining_time(mailbox.expires_at))
              |> assign(:active_tab, "html")
            
            {:ok, socket}
        end
    end
  end
  
  @impl true
  def handle_event("delete_message", _params, socket) do
    # Verify ownership
    if socket.assigns.is_owner do
      message = socket.assigns.message
      mailbox = socket.assigns.mailbox
      
      {:ok, _} = Elektrine.Email.delete_message(message)
      
      # Redirect to mailbox
      {:noreply,
       socket
       |> Phoenix.LiveView.put_flash(:info, "Message deleted successfully.")
       |> Phoenix.LiveView.push_navigate(to: ~p"/temp-mail/#{mailbox.token}")}
    else
      {:noreply, 
       socket
       |> Phoenix.LiveView.put_flash(:error, "You don't have permission to delete messages from this mailbox.")}
    end
  end
  
  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end
  
  @impl true
  def handle_event("refresh", _params, socket) do
    # Just reload the message with fresh data using the adapter
    message_id = socket.assigns.message.id
    
    case Elektrine.Email.get_message(message_id) do
      nil ->
        # Message not found, possibly deleted
        {:noreply, 
         socket
         |> Phoenix.LiveView.put_flash(:error, "Message not found.")
         |> Phoenix.LiveView.push_navigate(to: ~p"/temp-mail/#{socket.assigns.mailbox.token}")}
      
      message ->
        # Message found, update it
        {:noreply, assign(socket, :message, message)}
    end
  end
  
  @impl true
  def handle_info(:update_remaining_time, socket) do
    # Update the remaining time display
    mailbox = socket.assigns.mailbox
    
    {:noreply, 
     socket
     |> assign(:remaining_time, calculate_remaining_time(mailbox.expires_at))}
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