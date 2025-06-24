defmodule ElektrineWeb.TemporaryMailboxLive.Index do
  use ElektrineWeb, :live_view

  alias Elektrine.Email

  @impl true
  def mount(_params, session, socket) do
    # Preserve current_user if they're authenticated, otherwise set to nil
    _current_user = socket.assigns[:current_user]

    # Check if user has a temporary mailbox token in session
    case Map.get(session, "temporary_mailbox_token") do
      nil ->
        # No temporary mailbox, create one with domain awareness
        domain = get_request_domain_from_socket(socket)
        {:ok, mailbox} = Email.create_temporary_mailbox(24, domain)

        # Redirect to the controller that will set the session
        socket =
          socket
          |> Phoenix.LiveView.redirect(to: ~p"/temp-mail/#{mailbox.token}/set_token")

        {:ok, socket}

      token ->
        # User already has a mailbox, redirect to it
        socket =
          socket
          |> Phoenix.LiveView.redirect(to: ~p"/temp-mail/#{token}")

        {:ok, socket}
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
