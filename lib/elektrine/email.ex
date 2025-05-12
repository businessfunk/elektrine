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
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
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
end