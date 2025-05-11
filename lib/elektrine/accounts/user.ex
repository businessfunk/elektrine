defmodule Elektrine.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :password_hash, :string
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for user registration.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :password_confirmation])
    |> validate_required([:username, :password, :password_confirmation])
    |> validate_length(:username, min: 3, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/, message: "only letters, numbers, and underscores allowed")
    |> unique_constraint(:username)
    |> validate_length(:password, min: 8, max: 72)
    |> validate_confirmation(:password, message: "does not match password")
    |> hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    # We'll add the actual password hashing implementation later
    change(changeset, %{password_hash: Bcrypt.hash_pwd_salt(password)})
  end

  defp hash_password(changeset), do: changeset

  @doc """
  A changeset for changing the user account.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username])
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 30)
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
end
