defmodule ElektrineWeb.MailboxController do
  use ElektrineWeb, :controller

  alias Elektrine.Email
  alias Elektrine.Email.Mailbox

  def index(conn, _params) do
    user = conn.assigns.current_user
    mailboxes = Email.list_mailboxes(user.id)
    
    render(conn, :index, mailboxes: mailboxes)
  end

  def new(conn, _params) do
    changeset = %Mailbox{} |> Elektrine.Email.Mailbox.changeset(%{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"mailbox" => mailbox_params}) do
    user = conn.assigns.current_user
    
    # Add the user_id to the mailbox params
    mailbox_params = Map.put(mailbox_params, "user_id", user.id)
    
    # Set primary to false if not specified
    mailbox_params = Map.put_new(mailbox_params, "primary", "false")
    
    # Convert string "true"/"false" to boolean
    mailbox_params = if mailbox_params["primary"] == "true" do
      Map.put(mailbox_params, "primary", true)
    else
      Map.put(mailbox_params, "primary", false)
    end
    
    # If setting this mailbox as primary, unset any other primary mailboxes
    if mailbox_params["primary"] do
      unset_other_primary_mailboxes(user.id)
    end
    
    case Email.create_mailbox(mailbox_params) do
      {:ok, _mailbox} ->
        conn
        |> put_flash(:info, "Mailbox created successfully.")
        |> redirect(to: ~p"/mailboxes")
        
      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    mailbox = Email.get_mailbox(id, user.id)
    
    if mailbox do
      # Check if this is the only mailbox
      mailboxes = Email.list_mailboxes(user.id)
      
      if length(mailboxes) <= 1 do
        conn
        |> put_flash(:error, "Cannot delete your only mailbox.")
        |> redirect(to: ~p"/mailboxes")
      else
        case Email.delete_mailbox(mailbox) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Mailbox deleted successfully.")
            |> redirect(to: ~p"/mailboxes")
            
          {:error, _} ->
            conn
            |> put_flash(:error, "Failed to delete mailbox.")
            |> redirect(to: ~p"/mailboxes")
        end
      end
    else
      conn
      |> put_flash(:error, "Mailbox not found.")
      |> redirect(to: ~p"/mailboxes")
    end
  end

  def set_primary(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    mailbox = Email.get_mailbox(id, user.id)
    
    if mailbox do
      # Unset any other primary mailboxes
      unset_other_primary_mailboxes(user.id)
      
      # Set this one as primary
      case Email.update_mailbox(mailbox, %{primary: true}) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Primary mailbox updated successfully.")
          |> redirect(to: ~p"/mailboxes")
          
        {:error, _} ->
          conn
          |> put_flash(:error, "Failed to update primary mailbox.")
          |> redirect(to: ~p"/mailboxes")
      end
    else
      conn
      |> put_flash(:error, "Mailbox not found.")
      |> redirect(to: ~p"/mailboxes")
    end
  end
  
  # Helper to unset all other primary mailboxes
  defp unset_other_primary_mailboxes(user_id) do
    import Ecto.Query
    alias Elektrine.Repo
    
    primary_mailboxes = Mailbox
                        |> where(user_id: ^user_id, primary: true)
                        |> Repo.all()
    
    for mailbox <- primary_mailboxes do
      Email.update_mailbox(mailbox, %{primary: false})
    end
  end
end