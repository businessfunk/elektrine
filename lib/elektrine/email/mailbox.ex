defmodule Elektrine.Email.Mailbox do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "mailboxes" do
    field :email, :string

    belongs_to :user, Elektrine.Accounts.User
    has_many :messages, Elektrine.Email.Message

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new mailbox.
  """
  def changeset(mailbox, attrs) do
    mailbox
    |> cast(attrs, [:email, :user_id])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for a new orphaned mailbox (without a user).
  """
  def orphaned_changeset(mailbox, attrs) do
    mailbox
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
  end

  @doc """
  Creates a user's mailbox based on their username.
  """
  def create_for_user(user) do
    domain = Application.get_env(:elektrine, :postal)[:domain] || "elektrine.com"
    email = "#{user.username}@#{domain}"

    %Elektrine.Email.Mailbox{}
    |> changeset(%{email: email, user_id: user.id})
  end
end
