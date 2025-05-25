defmodule ElektrineWeb.EmailLive.Sent do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers
  import Ecto.Query

  alias Elektrine.Email
  alias Elektrine.Email.Message
  alias Elektrine.Repo

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    unread_count = Email.unread_count(mailbox.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, "Sent Messages")
     |> assign(:mailbox, mailbox)
     |> assign(:messages, list_sent_messages(mailbox.id))
     |> assign(:unread_count, unread_count)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    message = Email.get_message(id)
    
    if message && message.mailbox_id == socket.assigns.mailbox.id do
      {:ok, _} = Email.delete_message(message)
      
      {:noreply,
       socket
       |> put_flash(:info, "Message deleted successfully")
       |> assign(:messages, list_sent_messages(socket.assigns.mailbox.id))}
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

  defp list_sent_messages(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, status: "sent")
    |> order_by(desc: :inserted_at)
    |> limit(50)
    |> Repo.all()
  end
end