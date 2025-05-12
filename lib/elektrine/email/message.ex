defmodule Elektrine.Email.Message do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "email_messages" do
    field :message_id, :string
    field :from, :string
    field :to, :string
    field :cc, :string
    field :bcc, :string
    field :subject, :string
    field :text_body, :string
    field :html_body, :string
    field :status, :string, default: "received" # received, sent, draft
    field :read, :boolean, default: false
    field :metadata, :map, default: %{}
    
    belongs_to :mailbox, Elektrine.Email.Mailbox

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new email message.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:message_id, :from, :to, :cc, :bcc, :subject, :text_body, :html_body, :status, :read, :metadata, :mailbox_id])
    |> validate_required([:message_id, :from, :to, :mailbox_id])
    |> unique_constraint([:message_id, :mailbox_id])
    |> foreign_key_constraint(:mailbox_id)
  end
  
  @doc """
  Mark a message as read.
  """
  def read_changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [])
    |> put_change(:read, true)
  end
end