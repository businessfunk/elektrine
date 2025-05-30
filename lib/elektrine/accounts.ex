defmodule Elektrine.Accounts do
  @moduledoc """
  The Accounts context.
  Handles user accounts, authentication, and related functionality.
  """

  import Ecto.Query, warn: false
  alias Elektrine.Repo

  alias Elektrine.Accounts.User

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by username.

  Returns nil if the User does not exist.

  ## Examples

      iex> get_user_by_username("username")
      %User{}

      iex> get_user_by_username("nonexistent")
      nil

  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user(attrs \\ %{}) do
    result = %User{}
             |> User.registration_changeset(attrs)
             |> Repo.insert()

    case result do
      {:ok, user} ->
        # Create a mailbox for the user
        Elektrine.Email.create_mailbox(user)
        {:ok, user}
      error -> error
    end
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a user's password.

  ## Examples

      iex> update_user_password(user, %{password: "new password", password_confirmation: "new password"})
      {:ok, %User{}}

      iex> update_user_password(user, %{password: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(%User{} = user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user password changes.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs)
  end

  @doc """
  Authenticates a user by username and password.

  Returns `{:ok, user}` if the username and password are valid,
  or `{:error, :invalid_credentials}` if the username or password are invalid.

  ## Examples

      iex> authenticate_user("username", "correct_password")
      {:ok, %User{}}

      iex> authenticate_user("username", "wrong_password")
      {:error, :invalid_credentials}

      iex> authenticate_user("nonexistent", "any_password")
      {:error, :invalid_credentials}

  """
  def authenticate_user(username, password) when is_binary(username) and is_binary(password) do
    user = get_user_by_username(username)

    with %User{} <- user,
         true <- verify_password_hash(password, user.password_hash) do
      # Rehash with Argon2 if the current hash is bcrypt
      if is_bcrypt_hash?(user.password_hash) do
        user
        |> User.password_changeset(%{password: password, password_confirmation: password})
        |> Repo.update()
      end

      {:ok, user}
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  # Detects hash type and verifies password
  defp verify_password_hash(password, hash) do
    cond do
      is_bcrypt_hash?(hash) -> Bcrypt.verify_pass(password, hash)
      true -> Argon2.verify_pass(password, hash)
    end
  end

  # Simple heuristic to detect bcrypt hashes which start with "$2" or "$2a$"
  defp is_bcrypt_hash?(hash) when is_binary(hash) do
    String.starts_with?(hash, ["$2", "$2a$", "$2b$", "$2y$"])
  end
  defp is_bcrypt_hash?(_), do: false
end