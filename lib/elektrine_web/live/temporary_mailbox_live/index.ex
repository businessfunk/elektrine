defmodule ElektrineWeb.TemporaryMailboxLive.Index do
  use ElektrineWeb, :live_view
  
  alias Elektrine.Email
  alias Elektrine.Email.TemporaryMailbox
  
  @impl true
  def mount(_params, session, socket) do
    # Assign current_user as nil for layout
    socket = assign(socket, :current_user, nil)
    
    # Check if user has a temporary mailbox token in session
    case Map.get(session, "temporary_mailbox_token") do
      nil -> 
        # No temporary mailbox, create one
        {:ok, mailbox} = Email.create_temporary_mailbox()
        
        # Redirect to the controller that will set the session
        socket = 
          socket
          |> Phoenix.LiveView.put_flash(:info, "Created new temporary mailbox")
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