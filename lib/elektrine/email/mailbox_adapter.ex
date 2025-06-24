defmodule Elektrine.Email.MailboxAdapter do
  @moduledoc """
  Adapter module to unify operations between regular mailboxes and temporary mailboxes.
  This helps deal with database constraints by routing messages to the correct table.
  """

  alias Elektrine.Email.Message
  alias Elektrine.Email.Mailbox
  alias Elektrine.Email.TemporaryMailbox
  alias Elektrine.Repo
  import Ecto.Query

  @doc """
  Creates a message for a temporary mailbox.
  This method automatically detects if the mailbox is temporary or regular.
  """
  def create_message(attrs) do
    # Extract mailbox_id from attributes
    mailbox_id = Map.get(attrs, :mailbox_id) || Map.get(attrs, "mailbox_id")
    # Fix integer/string conversion - ensure mailbox_id is an integer
    mailbox_id = if is_binary(mailbox_id), do: String.to_integer(mailbox_id), else: mailbox_id

    # First, try to find in regular mailboxes
    mailbox = Repo.get(Mailbox, mailbox_id)

    if mailbox do
      # This is a regular mailbox, use standard create_message
      Elektrine.Email.create_message(attrs)
    else
      # Check if this is a temporary mailbox
      temp_mailbox = Repo.get(TemporaryMailbox, mailbox_id)

      if temp_mailbox do
        # Add the mailbox_type for temporary mailboxes
        attrs_with_type = Map.put(attrs, :mailbox_type, "temporary")

        # Insert the message with temporary mailbox type
        %Message{}
        |> Message.changeset(attrs_with_type)
        |> Repo.insert()
        |> case do
          {:ok, message} = result ->
            # Broadcast to the mailbox's PubSub topic
            Phoenix.PubSub.broadcast!(
              Elektrine.PubSub,
              "mailbox:#{mailbox_id}",
              {:new_email, message}
            )

            result

          error ->
            error
        end
      else
        # Neither regular nor temporary mailbox found
        {:error, :mailbox_not_found}
      end
    end
  end

  @doc """
  Gets a mailbox by ID, checking both regular and temporary mailbox tables.
  Returns the mailbox with a type indicator.
  """
  def get_mailbox(id) do
    # First check the regular mailbox table
    case Repo.get(Mailbox, id) do
      %Mailbox{} = mailbox ->
        {:regular, mailbox}

      nil ->
        # Check the temporary mailbox table
        case Repo.get(TemporaryMailbox, id) do
          %TemporaryMailbox{} = temp_mailbox -> {:temporary, temp_mailbox}
          nil -> nil
        end
    end
  end

  @doc """
  List messages for a mailbox with special handling for temporary mailboxes.
  """
  def list_messages(mailbox_id, type \\ :auto, limit \\ 50, offset \\ 0) do
    _mailbox_type =
      if type == :auto do
        case get_mailbox(mailbox_id) do
          {:regular, _} -> "regular"
          {:temporary, _} -> "temporary"
          # Default to regular if not found
          _ -> "regular"
        end
      else
        to_string(type)
      end

    # For now, we just query by mailbox_id without using mailbox_type
    # This allows both temporary and regular mailboxes to work
    Message
    |> where([m], m.mailbox_id == ^mailbox_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end
end
