defmodule Elektrine.Email.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "email_messages" do
    field :message_id, :string
    field :from, :string
    field :to, :string
    field :cc, :string
    field :bcc, :string
    field :subject, :string
    field :text_body, :string
    field :html_body, :string
    # received, sent, draft
    field :status, :string, default: "received"
    field :read, :boolean, default: false
    field :spam, :boolean, default: false
    field :archived, :boolean, default: false
    field :metadata, :map, default: %{}
    field :mailbox_type, :string, default: "regular"

    # Hey.com features
    field :screener_status, :string, default: "pending"
    field :sender_approved, :boolean, default: false
    field :category, :string, default: "inbox"
    field :set_aside_at, :utc_datetime
    field :set_aside_reason, :string
    field :reply_later_at, :utc_datetime
    field :reply_later_reminder, :boolean, default: false
    field :is_receipt, :boolean, default: false
    field :is_notification, :boolean, default: false
    field :is_newsletter, :boolean, default: false
    field :opened_at, :utc_datetime
    field :first_opened_at, :utc_datetime
    field :open_count, :integer, default: 0

    # Attachments
    field :attachments, :map, default: %{}
    field :has_attachments, :boolean, default: false

    belongs_to :mailbox, Elektrine.Email.Mailbox

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new email message.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :message_id,
      :from,
      :to,
      :cc,
      :bcc,
      :subject,
      :text_body,
      :html_body,
      :status,
      :read,
      :spam,
      :archived,
      :metadata,
      :mailbox_id,
      :mailbox_type,
      :screener_status,
      :sender_approved,
      :category,
      :set_aside_at,
      :set_aside_reason,
      :reply_later_at,
      :reply_later_reminder,
      :is_receipt,
      :is_notification,
      :is_newsletter,
      :opened_at,
      :first_opened_at,
      :open_count,
      :attachments,
      :has_attachments
    ])
    |> validate_required([:message_id, :from, :to, :mailbox_id])
    |> set_has_attachments()
    |> unique_constraint([:message_id, :mailbox_id])

    # No foreign key constraint anymore - we manually handle the association
  end

  # Automatically set has_attachments based on attachments field
  defp set_has_attachments(changeset) do
    case get_field(changeset, :attachments) do
      attachments when is_map(attachments) and map_size(attachments) > 0 ->
        put_change(changeset, :has_attachments, true)

      _ ->
        put_change(changeset, :has_attachments, false)
    end
  end

  @doc """
  Mark a message as read.
  """
  def read_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:read, true)
  end

  @doc """
  Mark a message as unread.
  """
  def unread_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:read, false)
  end

  @doc """
  Mark a message as spam.
  """
  def spam_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:spam, true)
  end

  @doc """
  Mark a message as not spam.
  """
  def unspam_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:spam, false)
  end

  @doc """
  Archive a message.
  """
  def archive_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:archived, true)
  end

  @doc """
  Unarchive a message.
  """
  def unarchive_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:archived, false)
  end

  @doc """
  Approve a sender for The Screener.
  """
  def approve_sender_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:screener_status, "approved")
    |> put_change(:sender_approved, true)
  end

  @doc """
  Reject a sender for The Screener.
  """
  def reject_sender_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:screener_status, "rejected")
  end

  @doc """
  Set aside a message for later.
  """
  def set_aside_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [:set_aside_reason])
    |> put_change(:category, "set_aside")
    |> put_change(:set_aside_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Move message back from set aside.
  """
  def unset_aside_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:category, "inbox")
    |> put_change(:set_aside_at, nil)
    |> put_change(:set_aside_reason, nil)
  end

  @doc """
  Set a message for reply later.
  """
  def reply_later_changeset(message, attrs) do
    message
    |> cast(attrs, [:reply_later_at, :reply_later_reminder])
    |> validate_required([:reply_later_at])
  end

  @doc """
  Clear reply later for a message.
  """
  def clear_reply_later_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:reply_later_at, nil)
    |> put_change(:reply_later_reminder, false)
  end

  @doc """
  Track when a message is opened.
  """
  def track_open_changeset(message, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset =
      message
      |> cast(attrs, [])
      |> put_change(:opened_at, now)
      |> put_change(:open_count, (message.open_count || 0) + 1)

    if is_nil(message.first_opened_at) do
      changeset |> put_change(:first_opened_at, now)
    else
      changeset
    end
  end
end
