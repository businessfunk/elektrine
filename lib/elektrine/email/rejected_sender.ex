defmodule Elektrine.Email.RejectedSender do
  use Ecto.Schema
  import Ecto.Changeset

  schema "rejected_senders" do
    field :email_address, :string
    field :rejected_at, :utc_datetime
    field :rejection_count, :integer, default: 1
    field :last_rejection_at, :utc_datetime
    field :notes, :string

    belongs_to :mailbox, Elektrine.Email.Mailbox

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new rejected sender.
  """
  def changeset(rejected_sender, attrs) do
    rejected_sender
    |> cast(attrs, [
      :email_address,
      :mailbox_id,
      :rejected_at,
      :rejection_count,
      :last_rejection_at,
      :notes
    ])
    |> validate_required([:email_address, :mailbox_id, :rejected_at])
    |> validate_format(:email_address, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email address"
    )
    |> unique_constraint([:email_address, :mailbox_id])
  end

  @doc """
  Update rejection tracking for a rejected sender.
  """
  def track_rejection_changeset(rejected_sender, attrs \\ %{}) do
    rejected_sender
    |> cast(attrs, [])
    |> put_change(:last_rejection_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:rejection_count, (rejected_sender.rejection_count || 0) + 1)
  end
end