defmodule Elektrine.Email.ApprovedSender do
  use Ecto.Schema
  import Ecto.Changeset

  schema "approved_senders" do
    field :email_address, :string
    field :approved_at, :utc_datetime
    field :last_email_at, :utc_datetime
    field :email_count, :integer, default: 0
    field :notes, :string

    belongs_to :mailbox, Elektrine.Email.Mailbox

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new approved sender.
  """
  def changeset(approved_sender, attrs) do
    approved_sender
    |> cast(attrs, [
      :email_address,
      :mailbox_id,
      :approved_at,
      :last_email_at,
      :email_count,
      :notes
    ])
    |> validate_required([:email_address, :mailbox_id, :approved_at])
    |> validate_format(:email_address, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email address"
    )
    |> unique_constraint([:email_address, :mailbox_id])
  end

  @doc """
  Update email tracking for an approved sender.
  """
  def track_email_changeset(approved_sender, attrs \\ %{}) do
    approved_sender
    |> cast(attrs, [])
    |> put_change(:last_email_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:email_count, (approved_sender.email_count || 0) + 1)
  end
end
