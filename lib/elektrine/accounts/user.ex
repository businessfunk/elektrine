defmodule Elektrine.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :password_hash, :string
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :avatar, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for user registration.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :password_confirmation])
    |> validate_required([:username, :password, :password_confirmation])
    |> validate_length(:username, min: 1, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/, message: "only letters, numbers, and underscores allowed")
    |> unique_constraint(:username)
    |> validate_length(:password, min: 8, max: 72)
    |> validate_confirmation(:password, message: "does not match password")
    |> hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    change(changeset, %{password_hash: Argon2.hash_pwd_salt(password)})
  end

  defp hash_password(changeset), do: changeset

  @doc """
  A changeset for changing the user account.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :avatar])
    |> validate_required([:username])
    |> validate_length(:username, min: 1, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/, message: "only letters, numbers, and underscores allowed")
    |> unique_constraint(:username)
  end

  @doc """
  A changeset for changing the user password.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password, :password_confirmation])
    |> validate_required([:password, :password_confirmation])
    |> validate_length(:password, min: 8, max: 72)
    |> validate_confirmation(:password, message: "does not match password")
    |> hash_password()
  end

  @doc """
  A changeset for importing users with pre-hashed passwords.
  For use in migrations only.
  """
  def import_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password_hash])
    |> validate_required([:username, :password_hash])
    |> validate_length(:username, min: 1, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/, message: "only letters, numbers, and underscores allowed")
    |> unique_constraint(:username)
  end
end
