defmodule Elektrine.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :password_hash, :string
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :avatar, :string
    field :last_username_change_at, :utc_datetime
    field :is_admin, :boolean, default: false
    field :banned, :boolean, default: false
    field :banned_at, :utc_datetime
    field :banned_reason, :string

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
    |> validate_username_not_alias()
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
    |> validate_username_change_frequency()
    |> validate_username_not_alias()
    |> unique_constraint(:username)
    |> maybe_update_username_change_timestamp()
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

  @doc """
  A changeset for admin user editing.
  """
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :avatar])
    |> validate_required([:username])
    |> validate_length(:username, min: 1, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/, message: "only letters, numbers, and underscores allowed")
    |> validate_username_not_alias()
    |> unique_constraint(:username)
  end

  @doc """
  A changeset for banning a user.
  """
  def ban_changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:banned_reason])
    |> put_change(:banned, true)
    |> put_change(:banned_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  A changeset for unbanning a user.
  """
  def unban_changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [])
    |> put_change(:banned, false)
    |> put_change(:banned_at, nil)
    |> put_change(:banned_reason, nil)
  end

  @doc """
  Checks if the user can change their username (only once per week).
  """
  def can_change_username?(%__MODULE__{last_username_change_at: nil}), do: true
  def can_change_username?(%__MODULE__{last_username_change_at: last_change}) do
    one_week_ago = DateTime.utc_now() |> DateTime.add(-7, :day)
    DateTime.compare(last_change, one_week_ago) == :lt
  end

  @doc """
  Returns the next allowed username change date.
  """
  def next_username_change_date(%__MODULE__{last_username_change_at: nil}), do: nil
  def next_username_change_date(%__MODULE__{last_username_change_at: last_change}) do
    DateTime.add(last_change, 7, :day)
  end

  # Private helper functions

  defp validate_username_not_alias(changeset) do
    username = get_field(changeset, :username)
    
    if username do
      # Check if this username would conflict with existing aliases on our domains
      allowed_domains = ["elektrine.com", "z.org"]
      
      # Check each domain for conflicts
      conflicts = Enum.any?(allowed_domains, fn domain ->
        alias_email = "#{username}@#{domain}"
        case Elektrine.Repo.get_by(Elektrine.Email.Alias, alias_email: alias_email, enabled: true) do
          nil -> false
          _alias -> true
        end
      end)
      
      if conflicts do
        add_error(changeset, :username, "this username conflicts with an existing email alias")
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_username_change_frequency(changeset) do
    case get_field(changeset, :username) do
      username when is_binary(username) ->
        user = changeset.data
        current_username = user.username
        
        # Only validate if username is actually changing
        if username != current_username do
          if can_change_username?(user) do
            changeset
          else
            next_change = next_username_change_date(user)
            days_remaining = DateTime.diff(next_change, DateTime.utc_now(), :day)
            
            add_error(changeset, :username, 
              "can only be changed once per week. Next change allowed in #{days_remaining + 1} day(s)")
          end
        else
          changeset
        end
      _ ->
        changeset
    end
  end

  defp maybe_update_username_change_timestamp(changeset) do
    case get_change(changeset, :username) do
      nil -> changeset
      _new_username ->
        user = changeset.data
        current_username = user.username
        new_username = get_field(changeset, :username)
        
        # Only update timestamp if username is actually changing
        if new_username != current_username do
          put_change(changeset, :last_username_change_at, DateTime.utc_now())
        else
          changeset
        end
    end
  end
end
