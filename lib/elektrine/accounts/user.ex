defmodule Elektrine.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  User schema for the application.
  
  ## Fields
  
  * `:username` - Primary identifier for login and forms the user's email address (username@elektrine.com)
  * `:recovery_email` - Alternative email for account recovery and notifications
  * `:password` - Virtual field for password input
  * `:password_confirmation` - Virtual field for password confirmation
  * `:hashed_password` - Encrypted password stored in the database
  """

  schema "users" do
    field :username, :string
    field :recovery_email, :string
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :hashed_password, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for registering a new user.
  
  Username is the primary identifier for login and will be used to form
  the user's email address (username@elektrine.com).
  The recovery_email field is used as an alternative contact method for recovery.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :recovery_email, :password])
    |> validate_required([:username, :recovery_email, :password])
    |> validate_recovery_email()
    |> validate_username()
    |> validate_password()
  end

  defp validate_recovery_email(changeset) do
    changeset
    |> validate_format(:recovery_email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:recovery_email, max: 160)
    |> unsafe_validate_unique(:recovery_email, Elektrine.Repo)
    |> unique_constraint(:recovery_email)
  end

  defp validate_username(changeset) do
    changeset
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/, message: "only letters, numbers, and underscores allowed")
    |> validate_length(:username, min: 3, max: 20)
    |> unsafe_validate_unique(:username, Elektrine.Repo)
    |> unique_constraint(:username)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 80)
    |> validate_format(:password, ~r/[a-z]/, message: "must have at least one lowercase character")
    |> validate_format(:password, ~r/[A-Z]/, message: "must have at least one uppercase character")
    |> validate_format(:password, ~r/[0-9]/, message: "must have at least one digit")
    |> prepare_changes(&hash_password/1)
  end

  defp hash_password(changeset) do
    password = get_change(changeset, :password)

    if password do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A changeset for updating the user.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :recovery_email])
    |> validate_required([:username, :recovery_email])
    |> validate_recovery_email()
    |> validate_username()
  end

  @doc """
  Verifies the password.
  """
  def valid_password?(%Elektrine.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  @doc """
  A changeset for changing the password.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password, :password_confirmation])
    |> validate_required([:password, :password_confirmation])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password()
  end
end
