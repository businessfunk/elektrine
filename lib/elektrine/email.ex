defmodule Elektrine.Email do
  @moduledoc """
  The Email context.
  This context handles all email-related functionality like managing mailboxes,
  sending/receiving emails, and storing/retrieving email messages.
  """

  import Ecto.Query, warn: false
  alias Elektrine.Repo

  alias Elektrine.Email.Mailbox
  alias Elektrine.Email.Message
  alias Elektrine.Email.TemporaryMailbox
  alias Elektrine.Accounts

  @doc """
  Gets a user's mailbox.
  Returns nil if the Mailbox does not exist.
  """
  def get_user_mailbox(user_id) do
    Mailbox
    |> where(user_id: ^user_id)
    |> Repo.one()
  end

  @doc """
  Gets a single mailbox.
  Returns nil if the Mailbox does not exist.
  """
  def get_mailbox(id), do: Repo.get(Mailbox, id)

  @doc """
  Gets a single mailbox for a specific user.
  Returns nil if the Mailbox does not exist for that user.
  """
  def get_mailbox(id, user_id) do
    Mailbox
    |> where(id: ^id, user_id: ^user_id)
    |> Repo.one()
  end

  @doc """
  Creates a mailbox for a user.
  """
  def create_mailbox(user) do
    Mailbox.create_for_user(user)
    |> Repo.insert()
  end

  @doc """
  Ensures a user has a mailbox, creating one if it doesn't exist.
  """
  def ensure_user_has_mailbox(user) do
    case get_user_mailbox(user.id) do
      nil -> create_mailbox(user)
      mailbox -> {:ok, mailbox}
    end
  end

  @doc """
  Returns the list of messages for a user.
  """
  def list_user_messages(user_id, limit \\ 50, offset \\ 0) do
    mailbox = get_user_mailbox(user_id)

    if mailbox do
      list_messages(mailbox.id, limit, offset)
    else
      []
    end
  end

  @doc """
  Returns the list of messages for a mailbox.
  """
  def list_messages(mailbox_id, limit \\ 50, offset \\ 0) do
    Message
    |> where(mailbox_id: ^mailbox_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns the list of unread messages for a user.
  """
  def list_user_unread_messages(user_id) do
    mailbox = get_user_mailbox(user_id)

    if mailbox do
      list_unread_messages(mailbox.id)
    else
      []
    end
  end

  @doc """
  Returns the list of unread messages for a mailbox.
  """
  def list_unread_messages(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, read: false)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single message.
  Returns nil if the Message does not exist.
  """
  def get_message(id), do: Repo.get(Message, id)

  @doc """
  Gets a single message for a specific mailbox.
  Returns nil if the Message does not exist for that mailbox.
  """
  def get_message(id, mailbox_id) do
    Message
    |> where(id: ^id, mailbox_id: ^mailbox_id)
    |> Repo.one()
  end

  @doc """
  Gets a single message by its message_id for a specific mailbox.
  Returns nil if the Message does not exist for that mailbox.
  This is used to prevent duplicate message creation.
  """
  def get_message_by_id(message_id, mailbox_id) do
    Message
    |> where(message_id: ^message_id, mailbox_id: ^mailbox_id)
    |> Repo.one()
  end

  @doc """
  Creates a message.
  """
  def create_message(attrs \\ %{}) do
    result = %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
    
    case result do
      {:ok, message} ->
        # Broadcast to any LiveViews monitoring this mailbox
        if Map.has_key?(attrs, :mailbox_id) do
          Phoenix.PubSub.broadcast!(
            Elektrine.PubSub,
            "mailbox:#{attrs.mailbox_id}",
            {:new_email, message}
          )
        end
        
        # Return the original result
        {:ok, message}
        
      error ->
        error
    end
  end

  @doc """
  Updates a message.
  """
  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a message as read.
  """
  def mark_as_read(%Message{} = message) do
    message
    |> Message.read_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes a message.
  """
  def delete_message(%Message{} = message) do
    Repo.delete(message)
  end

  @doc """
  Returns the unread message count for a user.
  """
  def user_unread_count(user_id) do
    mailbox = get_user_mailbox(user_id)

    if mailbox do
      unread_count(mailbox.id)
    else
      0
    end
  end

  @doc """
  Returns the unread message count for a mailbox.
  """
  def unread_count(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, read: false)
    |> Repo.aggregate(:count)
  end
  
  #
  # Temporary Mailbox Functions
  #
  
  @doc """
  Creates a new temporary mailbox with a random email address.
  The mailbox will expire after the specified duration (default: 24 hours).
  """
  def create_temporary_mailbox(expires_in_hours \\ 24) do
    # Set expiration time
    expires_at = DateTime.utc_now() |> DateTime.add(expires_in_hours * 60 * 60, :second)
    
    # Generate a random email and token
    email = TemporaryMailbox.generate_email()
    token = TemporaryMailbox.generate_token()
    
    # Create the temporary mailbox
    %TemporaryMailbox{}
    |> TemporaryMailbox.changeset(%{
      email: email,
      token: token,
      expires_at: expires_at
    })
    |> Repo.insert()
  end
  
  @doc """
  Gets a temporary mailbox by its token.
  Returns nil if the mailbox does not exist or has expired.
  """
  def get_temporary_mailbox_by_token(token) when is_binary(token) do
    now = DateTime.utc_now()
    
    TemporaryMailbox
    |> where([m], m.token == ^token and m.expires_at > ^now)
    |> Repo.one()
  end
  
  @doc """
  Gets a temporary mailbox by its email address.
  Returns nil if the mailbox does not exist or has expired.
  """
  def get_temporary_mailbox_by_email(email) when is_binary(email) do
    now = DateTime.utc_now()
    
    # First try exact match
    result = TemporaryMailbox
    |> where([m], m.email == ^email and m.expires_at > ^now)
    |> Repo.one()
    
    # If not found, try case-insensitive match
    if is_nil(result) do
      TemporaryMailbox
      |> where([m], fragment("lower(?)", m.email) == ^String.downcase(email) and m.expires_at > ^now)
      |> Repo.one()
    else
      result
    end
  end
  
  @doc """
  Lists all messages for a temporary mailbox identified by its token.
  Returns an empty list if the mailbox does not exist or has expired.
  """
  def list_temporary_mailbox_messages(token, limit \\ 50, offset \\ 0) do
    case get_temporary_mailbox_by_token(token) do
      nil -> []
      mailbox -> list_messages(mailbox.id, limit, offset)
    end
  end
  
  @doc """
  Extends the expiration time of a temporary mailbox.
  """
  def extend_temporary_mailbox(mailbox_id, additional_hours \\ 24) do
    mailbox = Repo.get(TemporaryMailbox, mailbox_id)
    
    if mailbox do
      # Calculate new expiration time
      new_expires_at = DateTime.utc_now() |> DateTime.add(additional_hours * 60 * 60, :second)
      
      # Update the mailbox
      mailbox
      |> TemporaryMailbox.changeset(%{expires_at: new_expires_at})
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end
  
  @doc """
  Deletes expired temporary mailboxes.
  """
  def cleanup_expired_temporary_mailboxes do
    now = DateTime.utc_now()
    
    {count, _} =
      TemporaryMailbox
      |> where([m], m.expires_at <= ^now)
      |> Repo.delete_all()
    
    {:ok, count}
  end
end