defmodule ElektrineWeb.API.TemporaryMailboxController do
  use ElektrineWeb, :controller

  alias Elektrine.Email
  alias Elektrine.Email.MailboxAdapter
  
  @doc """
  Creates a new temporary mailbox and returns its details.
  This is the entry point for Flutter app users.
  """
  def create(conn, _params) do
    # Create a new temporary mailbox with default 24 hour expiration
    case Email.create_temporary_mailbox() do
      {:ok, mailbox} ->
        render(conn, :show, mailbox: mailbox)
        
      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create temporary mailbox"})
    end
  end
  
  @doc """
  Gets a temporary mailbox by token.
  This allows the Flutter app to retrieve mailbox details and messages.
  """
  def show(conn, %{"token" => token}) do
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Temporary mailbox not found or expired"})
        
      mailbox ->
        # Get messages for this mailbox
        messages = MailboxAdapter.list_messages(mailbox.id, :temporary, 50)
        
        render(conn, :show, mailbox: mailbox, messages: messages)
    end
  end
  
  @doc """
  Extends the expiration time of a temporary mailbox.
  This allows Flutter app users to keep using a mailbox longer.
  """
  def extend(conn, %{"token" => token}) do
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Temporary mailbox not found or expired"})
        
      mailbox ->
        # Extend for another 24 hours
        case Email.extend_temporary_mailbox(mailbox.id) do
          {:ok, updated_mailbox} ->
            render(conn, :show, mailbox: updated_mailbox)
            
          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to extend mailbox expiration"})
        end
    end
  end
  
  @doc """
  Retrieves a specific message from a temporary mailbox.
  Allows Flutter app to display the message details.
  """
  def get_message(conn, %{"token" => token, "id" => id}) do
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Temporary mailbox not found or expired"})
        
      mailbox ->
        case Elektrine.Email.get_message(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Message not found"})
            
          message ->
            # Verify that the message belongs to this mailbox
            if message.mailbox_id == mailbox.id do
              # Mark message as read if it's not already
              unless message.read do
                {:ok, _} = Elektrine.Email.mark_as_read(message)
              end
              
              render(conn, :message, message: message)
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Message does not belong to this mailbox"})
            end
        end
    end
  end
  
  @doc """
  Deletes a message from a temporary mailbox.
  Allows Flutter app users to clean up unwanted messages.
  """
  def delete_message(conn, %{"token" => token, "id" => id}) do
    case Email.get_temporary_mailbox_by_token(token) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Temporary mailbox not found or expired"})
        
      mailbox ->
        case Elektrine.Email.get_message(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Message not found"})
            
          message ->
            # Verify that the message belongs to this mailbox
            if message.mailbox_id == mailbox.id do
              # Delete the message
              case Elektrine.Email.delete_message(message) do
                {:ok, _} ->
                  json(conn, %{status: "success", message: "Message deleted successfully"})
                  
                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to delete message"})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Message does not belong to this mailbox"})
            end
        end
    end
  end
end