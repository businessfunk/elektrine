defmodule Elektrine.Accounts do
  @moduledoc """
  The Accounts context handles user-related operations including registration,
  authentication, and user management.
  
  In this system, usernames are the primary identifiers for users and are used
  to form their email addresses (username@elektrine.com). The recovery_email field
  serves as an alternative contact method for account recovery and notifications.
  """

  import Ecto.Query, warn: false
  alias Elektrine.Repo
  alias Elektrine.Accounts.User

  @doc """
  Gets a user by username.
  
  Username is the primary identifier for users in the system.
  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Gets a user by recovery email.
  
  Recovery email is used as an alternative contact method.
  """
  def get_user_by_recovery_email(email) when is_binary(email) do
    Repo.get_by(User, recovery_email: email)
  end

  @doc """
  Gets a user by either username or recovery email.
  
  While username is the primary identifier, users can also log in using
  their alternative recovery email address.
  """
  def get_user_by_username_or_email(username_or_email) when is_binary(username_or_email) do
    if String.contains?(username_or_email, "@") do
      get_user_by_recovery_email(username_or_email)
    else
      get_user_by_username(username_or_email)
    end
  end

  @doc """
  Registers a user.
  
  ## Examples
      
      iex> register_user(%{username: "user123", recovery_email: "user@example.com", password: "Password123"})
      {:ok, %User{}}
      
      iex> register_user(%{username: "user", recovery_email: "invalid", password: "pass"})
      {:error, %Ecto.Changeset{}}
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs)
  end

  @doc """
  Gets a single user.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Authenticates a user.
  
  Returns `{:ok, user}` if a user exists with the given username/email
  and the password is valid. Otherwise, returns `{:error, reason}`.
  
  While username is the primary login method, users can also log in using
  their alternative recovery email address.
  """
  def authenticate_user(username_or_email, password) do
    user = get_user_by_username_or_email(username_or_email)
    
    cond do
      user && User.valid_password?(user, password) ->
        {:ok, user}
      user ->
        {:error, :bad_password}
      true ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns a list of users.
  """
  def list_users do
    Repo.all(User)
  end
end
