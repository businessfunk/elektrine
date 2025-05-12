defmodule ElektrineWeb.EmailLive.Show do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers

  alias Elektrine.Email

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    message = Email.get_message(id)
    unread_count = Email.unread_count(mailbox.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
    end

    cond do
      # Message not found
      is_nil(message) ->
        {:ok,
         socket
         |> put_flash(:error, "Message not found")
         |> redirect(to: ~p"/email/inbox")}

      # Message belongs to a different mailbox
      message.mailbox_id != mailbox.id ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have permission to view this message")
         |> redirect(to: ~p"/email/inbox")}

      # Message belongs to the user's mailbox
      true ->
        # Mark message as read if not already read
        unless message.read do
          {:ok, _} = Email.mark_as_read(message)
        end

        {:ok,
         socket
         |> assign(:page_title, message.subject)
         |> assign(:mailbox, mailbox)
         |> assign(:message, message)
         |> assign(:unread_count, unread_count)}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    message = Email.get_message(id)
    mailbox = socket.assigns.mailbox
    
    if message && message.mailbox_id == mailbox.id do
      {:ok, _} = Email.delete_message(message)
      
      {:noreply,
       socket
       |> put_flash(:info, "Message deleted successfully")
       |> redirect(to: ~p"/email/inbox")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Message not found")
       |> redirect(to: ~p"/email/inbox")}
    end
  end

  @impl true
  def handle_event("reply", _params, socket) do
    message = socket.assigns.message
    
    # Define a simple subject for replies
    subject = if String.starts_with?(message.subject, "Re: ") do
      message.subject
    else
      "Re: #{message.subject}"
    end
    
    # Redirect to compose with prefilled fields
    {:noreply,
     socket
     |> redirect(to: ~p"/email/compose?to=#{message.from}&subject=#{subject}")}
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