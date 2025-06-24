defmodule ElektrineWeb.EmailLive.Index do
  use ElektrineWeb, :live_view

  alias Elektrine.Email

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      user = socket.assigns.current_user
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_info({:new_email, _message}, socket) do
    # Update unread count
    {:noreply, update_unread_count(socket)}
  end

  defp apply_action(socket, :index, _params) do
    # Redirect to inbox
    socket
    |> push_navigate(to: ~p"/email/inbox")
  end

  defp update_unread_count(socket) do
    user = socket.assigns.current_user
    unread_count = Email.user_unread_count(user.id)
    assign(socket, unread_count: unread_count)
  end
end
