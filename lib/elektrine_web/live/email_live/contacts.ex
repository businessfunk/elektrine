defmodule ElektrineWeb.EmailLive.Contacts do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers

  alias Elektrine.Email

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)

    # Get approved and blocked senders for this mailbox
    contacts = Email.list_approved_senders(mailbox.id)
    blocked_senders = Email.list_blocked_senders(mailbox.id)

    socket =
      socket
      |> assign(:page_title, "Contacts")
      |> assign(:mailbox, mailbox)
      |> assign(:contacts, contacts)
      |> assign(:blocked_senders, blocked_senders)
      |> assign(:show_add_contact_modal, false)
      |> assign(:add_contact_email, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("show_add_contact_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_contact_modal, true)
     |> assign(:add_contact_email, "")}
  end

  @impl true
  def handle_event("close_add_contact_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_contact_modal, false)
     |> assign(:add_contact_email, "")}
  end

  @impl true
  def handle_event("add_contact", %{"email" => email}, socket) do
    case Email.create_approved_sender(%{
           email_address: String.trim(email),
           mailbox_id: socket.assigns.mailbox.id,
           approved_at: DateTime.utc_now() |> DateTime.truncate(:second)
         }) do
      {:ok, _contact} ->
        contacts = Email.list_approved_senders(socket.assigns.mailbox.id)

        {:noreply,
         socket
         |> assign(:contacts, contacts)
         |> assign(:show_add_contact_modal, false)
         |> assign(:add_contact_email, "")
         |> put_flash(:info, "Contact added successfully")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to add contact. Email may already exist or be invalid.")}
    end
  end

  @impl true
  def handle_event("remove_contact", %{"id" => id}, socket) do
    case Email.get_approved_sender(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Contact not found")}

      contact ->
        if contact.mailbox_id == socket.assigns.mailbox.id do
          {:ok, _} = Email.delete_approved_sender(contact)
          contacts = Email.list_approved_senders(socket.assigns.mailbox.id)

          {:noreply,
           socket
           |> assign(:contacts, contacts)
           |> put_flash(:info, "Contact removed successfully")}
        else
          {:noreply, put_flash(socket, :error, "Contact not found")}
        end
    end
  end

  @impl true
  def handle_event("block_sender", %{"email" => email}, socket) do
    Email.block_sender(email, socket.assigns.mailbox.id)
    blocked_senders = Email.list_blocked_senders(socket.assigns.mailbox.id)

    {:noreply,
     socket
     |> assign(:blocked_senders, blocked_senders)
     |> put_flash(:info, "Sender blocked successfully")}
  end

  @impl true
  def handle_event("unblock_sender", %{"email" => email}, socket) do
    Email.unblock_sender(email, socket.assigns.mailbox.id)
    blocked_senders = Email.list_blocked_senders(socket.assigns.mailbox.id)

    {:noreply,
     socket
     |> assign(:blocked_senders, blocked_senders)
     |> put_flash(:info, "Sender unblocked successfully")}
  end

  @impl true
  def handle_event(
        "update_contact_notes",
        %{"_target" => ["notes"], "notes" => notes} = params,
        socket
      ) do
    # Extract the contact ID from the form's phx-value-id
    contact_id = params["id"]

    case Email.get_approved_sender(contact_id) do
      nil ->
        {:noreply, socket}

      contact ->
        if contact.mailbox_id == socket.assigns.mailbox.id do
          case Email.update_approved_sender(contact, %{notes: String.trim(notes)}) do
            {:ok, _updated_contact} ->
              contacts = Email.list_approved_senders(socket.assigns.mailbox.id)

              {:noreply,
               socket
               |> assign(:contacts, contacts)}

            {:error, _changeset} ->
              {:noreply, socket}
          end
        else
          {:noreply, socket}
        end
    end
  end

  # Catch-all for other form change events
  @impl true
  def handle_event("update_contact_notes", _params, socket) do
    {:noreply, socket}
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
end
