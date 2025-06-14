defmodule ElektrineWeb.TemporaryMailboxLive.Index do
  use ElektrineWeb, :live_view
  
  alias Elektrine.Email
  alias Elektrine.Email.TemporaryMailbox
  
  @impl true
  def mount(_params, session, socket) do
    # Preserve current_user if they're authenticated, otherwise set to nil
    current_user = socket.assigns[:current_user]
    
    # Check if user has a temporary mailbox token in session
    case Map.get(session, "temporary_mailbox_token") do
      nil -> 
        # No temporary mailbox, create one
        {:ok, mailbox} = Email.create_temporary_mailbox()
        
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
end