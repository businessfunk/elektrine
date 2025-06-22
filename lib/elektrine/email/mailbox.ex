defmodule Elektrine.Email.Mailbox do
  use Ecto.Schema
  import Ecto.Changeset

  schema "mailboxes" do
    field :email, :string
    field :temporary, :boolean, default: false
    field :forward_to, :string
    field :forward_enabled, :boolean, default: false

    belongs_to :user, Elektrine.Accounts.User
    has_many :messages, Elektrine.Email.Message

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new mailbox.
  """
  def changeset(mailbox, attrs) do
    mailbox
    |> cast(attrs, [:email, :user_id, :forward_to, :forward_enabled])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
    |> foreign_key_constraint(:user_id)
    |> validate_forwarding()
  end

  @doc """
  Creates a changeset for updating mailbox forwarding settings.
  """
  def forwarding_changeset(mailbox, attrs) do
    mailbox
    |> cast(attrs, [:forward_to, :forward_enabled])
    |> validate_forwarding()
  end

  @doc """
  Creates a changeset for a new orphaned mailbox (without a user).
  """
  def orphaned_changeset(mailbox, attrs) do
    mailbox
    |> cast(attrs, [:email, :temporary])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
    |> put_change(:temporary, true) # Always mark orphaned mailboxes as temporary
  end

  @doc """
  Creates a user's mailbox based on their username.
  Optionally accepts a domain override, otherwise uses the configured default.
  """
  def create_for_user(user, domain \\ nil) do
    domain = domain || Application.get_env(:elektrine, :email)[:domain] || "elektrine.com"
    email = "#{user.username}@#{domain}"

    %Elektrine.Email.Mailbox{}
    |> changeset(%{email: email, user_id: user.id})
  end

  # Private helper functions

  defp validate_forwarding(changeset) do
    forward_enabled = get_field(changeset, :forward_enabled)
    forward_to = get_field(changeset, :forward_to)

    cond do
      forward_enabled && (is_nil(forward_to) || String.trim(forward_to) == "") ->
        add_error(changeset, :forward_to, "must be specified when forwarding is enabled")

      forward_to && String.trim(forward_to) != "" ->
        changeset
        |> validate_format(:forward_to, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email format")
        |> validate_not_self_forwarding()

      true ->
        changeset
    end
  end

  defp validate_not_self_forwarding(changeset) do
    email = get_field(changeset, :email)
    forward_to = get_field(changeset, :forward_to)

    if email && forward_to && String.downcase(email) == String.downcase(forward_to) do
      add_error(changeset, :forward_to, "cannot forward to the same email address")
    else
      changeset
    end
  end
end
