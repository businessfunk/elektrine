defmodule ElektrineWeb.EmailLive.TempMail do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers

  alias Elektrine.Email

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    unread_count = Email.unread_count(mailbox.id)

    # Subscribe to user's PubSub topic
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
    end

    case socket.assigns.live_action do
      :index ->
        handle_index(socket, mailbox, unread_count)

      :show ->
        handle_show(socket, params, mailbox, unread_count)

      :message ->
        handle_message(socket, params, mailbox, unread_count)
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    case socket.assigns.live_action do
      :index ->
        {:noreply, handle_index_params(socket)}

      :show ->
        handle_show_params(socket, params)

      :message ->
        handle_message_params(socket, params)
    end
  end

  defp handle_index(socket, mailbox, unread_count) do
    user_id = socket.assigns.current_user.id
    existing_temp_mailbox = Email.get_user_temporary_mailbox(user_id)

    {:ok,
     socket
     |> assign(:page_title, "Temporary Email")
     |> assign(:mailbox, mailbox)
     |> assign(:unread_count, unread_count)
     |> assign(:temp_mailboxes, [])
     |> assign(:existing_temp_mailbox, existing_temp_mailbox)
     |> assign(:current_temp_mailbox, nil)
     |> assign(:temp_messages, [])}
  end

  defp handle_index_params(socket) do
    user_id = socket.assigns.current_user.id
    existing_temp_mailbox = Email.get_user_temporary_mailbox(user_id)

    socket
    |> assign(:temp_mailboxes, [])
    |> assign(:existing_temp_mailbox, existing_temp_mailbox)
    |> assign(:current_temp_mailbox, nil)
    |> assign(:temp_messages, [])
  end

  defp handle_show_params(socket, %{"token" => token}) do
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Temporary mailbox not found or expired")
         |> push_navigate(to: ~p"/email/temp")}

      temp_mailbox ->
        messages = Email.list_temporary_mailbox_messages(token)

        # Subscribe to temp mailbox updates
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Elektrine.PubSub, "mailbox:#{temp_mailbox.id}")
        end

        {:noreply,
         socket
         |> assign(:page_title, "Temp Mailbox - #{temp_mailbox.email}")
         |> assign(:current_temp_mailbox, temp_mailbox)
         |> assign(:temp_messages, messages)
         |> assign(:temp_mailboxes, [])}
    end
  end

  defp handle_message_params(socket, %{"token" => token, "id" => id}) do
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Temporary mailbox not found or expired")
         |> push_navigate(to: ~p"/email/temp")}

      temp_mailbox ->
        case Email.get_message(id) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, "Message not found")
             |> push_navigate(to: ~p"/email/temp/#{token}")}

          message ->
            {:noreply,
             socket
             |> assign(:page_title, "Message - #{message.subject}")
             |> assign(:current_temp_mailbox, temp_mailbox)
             |> assign(:current_message, message)
             |> assign(:temp_messages, [])
             |> assign(:temp_mailboxes, [])}
        end
    end
  end

  defp handle_show(socket, %{"token" => token}, mailbox, unread_count) do
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Temporary mailbox not found or expired")
         |> push_navigate(to: ~p"/email/temp")}

      temp_mailbox ->
        messages = Email.list_temporary_mailbox_messages(token)

        # Subscribe to temp mailbox updates
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Elektrine.PubSub, "mailbox:#{temp_mailbox.id}")
        end

        {:ok,
         socket
         |> assign(:page_title, "Temp Mailbox - #{temp_mailbox.email}")
         |> assign(:mailbox, mailbox)
         |> assign(:unread_count, unread_count)
         |> assign(:current_temp_mailbox, temp_mailbox)
         |> assign(:temp_messages, messages)
         |> assign(:temp_mailboxes, [])}
    end
  end

  defp handle_message(socket, %{"token" => token, "id" => id}, mailbox, unread_count) do
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Temporary mailbox not found or expired")
         |> push_navigate(to: ~p"/email/temp")}

      temp_mailbox ->
        case Email.get_message(id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Message not found")
             |> push_navigate(to: ~p"/email/temp/#{token}")}

          message ->
            {:ok,
             socket
             |> assign(:page_title, "Message - #{message.subject}")
             |> assign(:mailbox, mailbox)
             |> assign(:unread_count, unread_count)
             |> assign(:current_temp_mailbox, temp_mailbox)
             |> assign(:current_message, message)
             |> assign(:temp_messages, [])
             |> assign(:temp_mailboxes, [])}
        end
    end
  end

  @impl true
  def handle_event("create_temp_mailbox", params, socket) do
    expires_in = Map.get(params, "expires_in", "24") |> String.to_integer()
    user_id = socket.assigns.current_user.id
    
    case Email.get_or_create_user_temporary_mailbox(user_id, expires_in) do
      {:ok, temp_mailbox} ->
        {:noreply,
         socket
         |> put_flash(:info, "Temporary mailbox ready")
         |> push_navigate(to: ~p"/email/temp/#{temp_mailbox.token}")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to create temporary mailbox")}
    end
  end

  @impl true
  def handle_event("reset_temp_mailbox", _params, socket) do
    user_id = socket.assigns.current_user.id
    Email.reset_user_temporary_mailbox(user_id)
    
    {:noreply,
     socket
     |> put_flash(:info, "Temporary mailbox reset successfully")
     |> push_navigate(to: ~p"/email/temp")}
  end

  @impl true
  def handle_event("delete_message", %{"id" => id}, socket) do
    message = Email.get_message(id)

    if message do
      {:ok, _} = Email.delete_message(message)

      # Refresh messages
      token = socket.assigns.current_temp_mailbox.token
      messages = Email.list_temporary_mailbox_messages(token)

      {:noreply,
       socket
       |> assign(:temp_messages, messages)
       |> put_flash(:info, "Message deleted successfully")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:new_email, _message}, socket) do
    # Update unread count when new email arrives
    unread_count = Email.unread_count(socket.assigns.mailbox.id)

    # Also refresh temp messages if we're viewing a temp mailbox
    socket =
      if socket.assigns[:current_temp_mailbox] do
        token = socket.assigns.current_temp_mailbox.token
        messages = Email.list_temporary_mailbox_messages(token)
        assign(socket, :temp_messages, messages)
      else
        socket
      end

    {:noreply, assign(socket, :unread_count, unread_count)}
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

      mailbox ->
        mailbox
    end
  end

  defp format_expiry(expires_at) do
    case DateTime.diff(expires_at, DateTime.utc_now()) do
      diff when diff > 0 ->
        hours = div(diff, 3600)
        minutes = div(rem(diff, 3600), 60)

        cond do
          hours > 24 -> "#{div(hours, 24)} days"
          hours > 0 -> "#{hours} hours"
          minutes > 0 -> "#{minutes} minutes"
          true -> "less than a minute"
        end

      _ ->
        "Expired"
    end
  end
end
