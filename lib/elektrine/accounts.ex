defmodule Elektrine.Accounts do
  @moduledoc """
  The Accounts context.
  Handles user accounts, authentication, and related functionality.
  """

  import Ecto.Query, warn: false
  alias Elektrine.Repo

  alias Elektrine.Accounts.User
  alias Elektrine.Accounts.AccountDeletionRequest
  alias Elektrine.Accounts.TwoFactor
  alias Elektrine.Accounts.InviteCode
  alias Elektrine.Accounts.InviteCodeUse

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
    result =
      %User{}
      |> User.registration_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, user} ->
        # Create a mailbox for the user
        Elektrine.Email.create_mailbox(user)
        {:ok, user}

      error ->
        error
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

    with %User{banned: false} <- user,
         true <- verify_password_hash(password, user.password_hash) do
      # Rehash with Argon2 if the current hash is bcrypt
      if is_bcrypt_hash?(user.password_hash) do
        user
        |> User.password_changeset(%{password: password, password_confirmation: password})
        |> Repo.update()
      end

      {:ok, user}
    else
      %User{banned: true} -> {:error, :banned}
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

  @doc """
  Updates a user's admin status.

  ## Examples

      iex> update_user_admin_status(user, true)
      {:ok, %User{}}

      iex> update_user_admin_status(user, false)
      {:ok, %User{}}

  """
  def update_user_admin_status(%User{} = user, is_admin) when is_boolean(is_admin) do
    user
    |> Ecto.Changeset.cast(%{is_admin: is_admin}, [:is_admin])
    |> Repo.update()
  end

  @doc """
  Creates a user (admin only).

  ## Examples

      iex> admin_create_user(%{username: "newuser", password: "password123", password_confirmation: "password123"})
      {:ok, %User{}}

      iex> admin_create_user(%{username: ""})
      {:error, %Ecto.Changeset{}}

  """
  def admin_create_user(attrs \\ %{}) do
    result =
      %User{}
      |> User.admin_registration_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, user} ->
        # Create a mailbox for the user
        Elektrine.Email.create_mailbox(user)
        {:ok, user}

      error ->
        error
    end
  end

  @doc """
  Updates a user (admin only).

  ## Examples

      iex> admin_update_user(user, %{username: "new_username"})
      {:ok, %User{}}

      iex> admin_update_user(user, %{username: ""})
      {:error, %Ecto.Changeset{}}

  """
  def admin_update_user(%User{} = user, attrs) do
    user
    |> User.admin_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Bans a user with an optional reason.

  ## Examples

      iex> ban_user(user, %{banned_reason: "Violation of terms"})
      {:ok, %User{}}

      iex> ban_user(user)
      {:ok, %User{}}

  """
  def ban_user(%User{} = user, attrs \\ %{}) do
    user
    |> User.ban_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Unbans a user.

  ## Examples

      iex> unban_user(user)
      {:ok, %User{}}

  """
  def unban_user(%User{} = user) do
    user
    |> User.unban_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes a user and all associated data.

  ## Examples

      iex> admin_delete_user(user)
      {:ok, %User{}}

      iex> admin_delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def admin_delete_user(%User{} = user) do
    # Delete all user's data first
    Repo.transaction(fn ->
      # Delete user's messages through their mailboxes
      from(m in Elektrine.Email.Message,
        join: mb in Elektrine.Email.Mailbox,
        on: m.mailbox_id == mb.id,
        where: mb.user_id == ^user.id
      )
      |> Repo.delete_all()

      # Delete user's mailboxes
      from(mb in Elektrine.Email.Mailbox, where: mb.user_id == ^user.id)
      |> Repo.delete_all()

      # Delete user's email aliases  
      from(a in Elektrine.Email.Alias, where: a.user_id == ^user.id)
      |> Repo.delete_all()

      # Delete user's approved senders (through mailboxes)
      from(as in Elektrine.Email.ApprovedSender,
        join: mb in Elektrine.Email.Mailbox,
        on: as.mailbox_id == mb.id,
        where: mb.user_id == ^user.id
      )
      |> Repo.delete_all()

      # Finally delete the user
      case Repo.delete(user) do
        {:ok, user} -> user
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user admin changes.

  ## Examples

      iex> change_user_admin(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_admin(%User{} = user, attrs \\ %{}) do
    User.admin_changeset(user, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for creating a user (admin only).

  ## Examples

      iex> change_user_admin_registration(%User{})
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_admin_registration(%User{} = user, attrs \\ %{}) do
    User.admin_registration_changeset(user, attrs)
  end

  # Account Deletion Request functions

  @doc """
  Creates an account deletion request.

  ## Examples

      iex> create_deletion_request(user, %{reason: "No longer needed"})
      {:ok, %AccountDeletionRequest{}}

      iex> create_deletion_request(user, %{})
      {:error, %Ecto.Changeset{}}

  """
  def create_deletion_request(%User{} = user, attrs \\ %{}) do
    attrs = Map.put(attrs, :user_id, user.id)
    attrs = Map.put(attrs, :requested_at, DateTime.utc_now() |> DateTime.truncate(:second))

    %AccountDeletionRequest{}
    |> AccountDeletionRequest.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a user's pending deletion request.

  ## Examples

      iex> get_pending_deletion_request(user)
      %AccountDeletionRequest{}

      iex> get_pending_deletion_request(user)
      nil

  """
  def get_pending_deletion_request(%User{} = user) do
    Repo.get_by(AccountDeletionRequest, user_id: user.id, status: "pending")
  end

  @doc """
  Lists all account deletion requests.

  ## Examples

      iex> list_deletion_requests()
      [%AccountDeletionRequest{}, ...]

  """
  def list_deletion_requests do
    from(r in AccountDeletionRequest,
      join: u in User,
      on: r.user_id == u.id,
      left_join: admin in User,
      on: r.reviewed_by_id == admin.id,
      select: %{r | user: u, reviewed_by: admin},
      order_by: [desc: r.requested_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single deletion request.

  ## Examples

      iex> get_deletion_request!(123)
      %AccountDeletionRequest{}

      iex> get_deletion_request!(456)
      ** (Ecto.NoResultsError)

  """
  def get_deletion_request!(id) do
    from(r in AccountDeletionRequest,
      join: u in User,
      on: r.user_id == u.id,
      left_join: admin in User,
      on: r.reviewed_by_id == admin.id,
      where: r.id == ^id,
      select: %{r | user: u, reviewed_by: admin}
    )
    |> Repo.one!()
  end

  @doc """
  Reviews an account deletion request (approve or deny).

  ## Examples

      iex> review_deletion_request(request, admin, "approved", %{admin_notes: "Approved"})
      {:ok, %AccountDeletionRequest{}}

      iex> review_deletion_request(request, admin, "denied", %{admin_notes: "Invalid reason"})
      {:ok, %AccountDeletionRequest{}}

  """
  def review_deletion_request(
        %AccountDeletionRequest{} = request,
        %User{} = admin,
        status,
        attrs \\ %{}
      ) do
    review_attrs = %{
      status: status,
      reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      reviewed_by_id: admin.id,
      admin_notes: Map.get(attrs, :admin_notes)
    }

    result =
      request
      |> AccountDeletionRequest.review_changeset(review_attrs)
      |> Repo.update()

    case result do
      {:ok, updated_request} when status == "approved" ->
        # If approved, delete the user account
        user = get_user!(request.user_id)

        case admin_delete_user(user) do
          {:ok, _user} -> {:ok, updated_request}
          {:error, _changeset} -> {:error, "Failed to delete user account"}
        end

      {:ok, updated_request} ->
        {:ok, updated_request}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Two-Factor Authentication functions

  @doc """
  Initiates 2FA setup for a user by generating a secret and backup codes.
  
  Returns the secret and provisioning URI for QR code generation.
  """
  def initiate_two_factor_setup(%User{} = user) do
    try do
      secret = TwoFactor.generate_secret()
      backup_codes = TwoFactor.generate_backup_codes()
      provisioning_uri = TwoFactor.generate_provisioning_uri(secret, user.username)
      
      {:ok, %{secret: secret, backup_codes: backup_codes, provisioning_uri: provisioning_uri}}
    rescue
      _ -> {:error, :setup_failed}
    end
  end

  @doc """
  Enables 2FA for a user after verifying the TOTP code.
  """
  def enable_two_factor(%User{} = user, secret, backup_codes, totp_code) do
    if TwoFactor.verify_totp(secret, totp_code) do
      user
      |> User.enable_two_factor_changeset(%{
        two_factor_secret: secret,
        two_factor_backup_codes: backup_codes
      })
      |> Repo.update()
    else
      {:error, :invalid_totp_code}
    end
  end

  @doc """
  Disables 2FA for a user.
  """
  def disable_two_factor(%User{} = user) do
    user
    |> User.disable_two_factor_changeset()
    |> Repo.update()
  end

  @doc """
  Verifies a 2FA code (TOTP or backup code) for a user.
  """
  def verify_two_factor_code(%User{two_factor_enabled: true} = user, code) do
    cond do
      TwoFactor.verify_totp(user.two_factor_secret, code) ->
        {:ok, :totp}

      user.two_factor_backup_codes != nil ->
        case TwoFactor.verify_backup_code(user.two_factor_backup_codes, code) do
          {:ok, remaining_codes} ->
            # Update user with remaining backup codes
            user
            |> User.update_backup_codes_changeset(remaining_codes)
            |> Repo.update()
            
            {:ok, :backup_code}

          {:error, :invalid} ->
            {:error, :invalid_code}
        end

      true ->
        {:error, :invalid_code}
    end
  end

  def verify_two_factor_code(%User{two_factor_enabled: false}, _code) do
    {:error, :two_factor_not_enabled}
  end

  @doc """
  Regenerates backup codes for a user with 2FA enabled.
  """
  def regenerate_backup_codes(%User{two_factor_enabled: true} = user) do
    backup_codes = TwoFactor.generate_backup_codes()
    
    result = 
      user
      |> User.update_backup_codes_changeset(backup_codes)
      |> Repo.update()
    
    case result do
      {:ok, updated_user} -> {:ok, {updated_user, backup_codes}}
      error -> error
    end
  end

  def regenerate_backup_codes(%User{two_factor_enabled: false}) do
    {:error, :two_factor_not_enabled}
  end

  ## Invite Codes

  @doc """
  Returns the list of invite codes.
  """
  def list_invite_codes do
    InviteCode
    |> order_by(desc: :inserted_at)
    |> preload(:created_by)
    |> Repo.all()
  end

  @doc """
  Gets a single invite code.

  Returns nil if the InviteCode does not exist.
  """
  def get_invite_code(id), do: Repo.get(InviteCode, id) |> Repo.preload(:created_by)

  @doc """
  Gets an invite code by its code string.

  Returns nil if the InviteCode does not exist.
  """
  def get_invite_code_by_code(code) do
    InviteCode
    |> where([i], i.code == ^code)
    |> preload(:created_by)
    |> Repo.one()
  end

  @doc """
  Creates an invite code.
  """
  def create_invite_code(attrs \\ %{}) do
    # Convert atom keys to string keys
    attrs = 
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.into(%{})
    
    # Only generate code if not provided
    attrs = 
      if attrs["code"] == nil || attrs["code"] == "" do
        Map.put(attrs, "code", InviteCode.generate_code())
      else
        attrs
      end
    
    %InviteCode{}
    |> InviteCode.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an invite code.
  """
  def update_invite_code(%InviteCode{} = invite_code, attrs) do
    invite_code
    |> InviteCode.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an invite code.
  """
  def delete_invite_code(%InviteCode{} = invite_code) do
    Repo.delete(invite_code)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking invite code changes.
  """
  def change_invite_code(%InviteCode{} = invite_code, attrs \\ %{}) do
    InviteCode.changeset(invite_code, attrs)
  end

  @doc """
  Validates and uses an invite code for a user registration.
  """
  def use_invite_code(code, user_id) do
    with %InviteCode{} = invite_code <- get_invite_code_by_code(code),
         true <- InviteCode.valid_for_use?(invite_code) do
      Repo.transaction(fn ->
        # Create the usage record
        %InviteCodeUse{}
        |> InviteCodeUse.changeset(%{invite_code_id: invite_code.id, user_id: user_id})
        |> Repo.insert!()

        # Increment the uses count
        invite_code
        |> Ecto.Changeset.change(uses_count: invite_code.uses_count + 1)
        |> Repo.update!()
      end)
    else
      nil -> {:error, :invalid_code}
      false -> {:error, :code_not_valid}
    end
  end

  @doc """
  Checks if an invite code is valid for use.
  """
  def validate_invite_code(code) do
    case get_invite_code_by_code(code) do
      nil -> {:error, :invalid_code}
      %InviteCode{} = invite_code ->
        if InviteCode.valid_for_use?(invite_code) do
          {:ok, invite_code}
        else
          cond do
            !invite_code.is_active -> {:error, :code_inactive}
            InviteCode.expired?(invite_code) -> {:error, :code_expired}
            InviteCode.exhausted?(invite_code) -> {:error, :code_exhausted}
            true -> {:error, :code_not_valid}
          end
        end
    end
  end

  @doc """
  Gets statistics for invite codes.
  """
  def get_invite_code_stats do
    %{
      total: Repo.aggregate(InviteCode, :count),
      active: Repo.aggregate(from(i in InviteCode, where: i.is_active == true), :count),
      expired: Repo.aggregate(from(i in InviteCode, where: not is_nil(i.expires_at) and i.expires_at < ^DateTime.utc_now()), :count),
      exhausted: Repo.aggregate(from(i in InviteCode, where: i.uses_count >= i.max_uses), :count)
    }
  end
end
