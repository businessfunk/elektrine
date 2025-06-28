defmodule ElektrineWeb.UserSettingsController do
  use ElektrineWeb, :controller

  alias Elektrine.Accounts

  plug :assign_user

  def edit(conn, _params) do
    user = conn.assigns.current_user
    changeset = Accounts.change_user(user)
    pending_deletion = Accounts.get_pending_deletion_request(user)
    render(conn, :edit, changeset: changeset, pending_deletion: pending_deletion)
  end

  def update(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user

    # Handle avatar upload if present
    {user_params, upload_error} = handle_avatar_upload(user_params, user)

    case {upload_error, Accounts.update_user(user, user_params)} do
      {nil, {:ok, _user}} ->
        conn
        |> put_flash(:info, "User updated successfully.")
        |> redirect(to: ~p"/account")

      {upload_error, {:ok, _user}} when upload_error != nil ->
        conn
        |> put_flash(:error, upload_error)
        |> redirect(to: ~p"/account")

      {upload_error, {:error, changeset}} ->
        conn = if upload_error, do: put_flash(conn, :error, upload_error), else: conn
        render(conn, :edit, changeset: changeset)
    end
  end

  def edit_password(conn, _params) do
    user = conn.assigns.current_user
    changeset = Accounts.change_user_password(user)
    render(conn, :edit_password, changeset: changeset)
  end

  def update_password(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user

    case Accounts.update_user_password(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> redirect(to: ~p"/account")

      {:error, changeset} ->
        render(conn, :edit_password, changeset: changeset)
    end
  end

  def delete(conn, _params) do
    render(conn, :delete)
  end

  def confirm_delete(conn, %{"confirmation" => confirmation, "reason" => reason}) do
    user = conn.assigns.current_user

    if confirmation == user.username do
      # Check if user already has a pending deletion request
      case Accounts.get_pending_deletion_request(user) do
        nil ->
          # Create new deletion request
          case Accounts.create_deletion_request(user, %{reason: reason}) do
            {:ok, _request} ->
              conn
              |> put_flash(
                :info,
                "Your account deletion request has been submitted and is pending admin approval."
              )
              |> redirect(to: ~p"/account")

            {:error, _changeset} ->
              conn
              |> put_flash(
                :error,
                "There was an error submitting your deletion request. Please try again."
              )
              |> redirect(to: ~p"/account/delete")
          end

        _existing_request ->
          conn
          |> put_flash(:error, "You already have a pending account deletion request.")
          |> redirect(to: ~p"/account")
      end
    else
      conn
      |> put_flash(:error, "Username confirmation does not match. Request not submitted.")
      |> redirect(to: ~p"/account/delete")
    end
  end

  def confirm_delete(conn, %{"confirmation" => confirmation}) do
    # Handle case where reason is not provided
    confirm_delete(conn, %{"confirmation" => confirmation, "reason" => ""})
  end

  def two_factor_setup(conn, _params) do
    user = conn.assigns.current_user
    
    if user.two_factor_enabled do
      redirect(conn, to: ~p"/account/two_factor")
    else
      case Accounts.initiate_two_factor_setup(user) do
        {:ok, setup_data} ->
          conn
          |> put_session(:two_factor_setup_secret, setup_data.secret)
          |> put_session(:two_factor_setup_backup_codes, setup_data.backup_codes)
          |> render(:two_factor_setup, 
            secret: setup_data.secret,
            backup_codes: setup_data.backup_codes,
            provisioning_uri: setup_data.provisioning_uri
          )
        
        {:error, _} ->
          conn
          |> put_flash(:error, "Failed to initiate two-factor authentication setup.")
          |> redirect(to: ~p"/account")
      end
    end
  end

  def two_factor_enable(conn, %{"two_factor" => %{"code" => code}}) do
    user = conn.assigns.current_user
    secret = get_session(conn, :two_factor_setup_secret)
    backup_codes = get_session(conn, :two_factor_setup_backup_codes)

    if secret && backup_codes do
      case Accounts.enable_two_factor(user, secret, backup_codes, code) do
        {:ok, _user} ->
          conn
          |> delete_session(:two_factor_setup_secret)
          |> delete_session(:two_factor_setup_backup_codes)
          |> put_flash(:info, "Two-factor authentication has been enabled successfully!")
          |> redirect(to: ~p"/account/two_factor")

        {:error, :invalid_totp_code} ->
          conn
          |> put_flash(:error, "Invalid authentication code. Please try again.")
          |> render(:two_factor_setup,
            secret: secret,
            backup_codes: backup_codes,
            provisioning_uri: Elektrine.Accounts.TwoFactor.generate_provisioning_uri(secret, user.username),
            error: "Invalid authentication code"
          )

        {:error, _} ->
          conn
          |> put_flash(:error, "Failed to enable two-factor authentication.")
          |> redirect(to: ~p"/account")
      end
    else
      conn
      |> put_flash(:error, "Two-factor authentication setup session expired.")
      |> redirect(to: ~p"/account/two_factor/setup")
    end
  end

  def two_factor_manage(conn, _params) do
    user = conn.assigns.current_user
    
    if user.two_factor_enabled do
      backup_codes_count = length(user.two_factor_backup_codes || [])
      render(conn, :two_factor_manage, backup_codes_count: backup_codes_count)
    else
      redirect(conn, to: ~p"/account/two_factor/setup")
    end
  end

  def two_factor_disable(conn, %{"two_factor" => %{"code" => code, "current_password" => password}}) do
    user = conn.assigns.current_user

    with {:ok, _verified_user} <- Accounts.authenticate_user(user.username, password),
         {:ok, _} <- Accounts.verify_two_factor_code(user, code),
         {:ok, _updated_user} <- Accounts.disable_two_factor(user) do
      
      conn
      |> put_flash(:info, "Two-factor authentication has been disabled.")
      |> redirect(to: ~p"/account")
    else
      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid password.")
        |> redirect(to: ~p"/account/two_factor")

      {:error, :invalid_code} ->
        conn
        |> put_flash(:error, "Invalid authentication code.")
        |> redirect(to: ~p"/account/two_factor")

      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to disable two-factor authentication.")
        |> redirect(to: ~p"/account/two_factor")
    end
  end

  def two_factor_regenerate_codes(conn, %{"two_factor" => %{"code" => code}}) do
    user = conn.assigns.current_user

    with {:ok, _} <- Accounts.verify_two_factor_code(user, code),
         {:ok, {_updated_user, new_backup_codes}} <- Accounts.regenerate_backup_codes(user) do
      
      render(conn, :two_factor_new_codes, backup_codes: new_backup_codes)
    else
      {:error, :invalid_code} ->
        conn
        |> put_flash(:error, "Invalid authentication code.")
        |> redirect(to: ~p"/account/two_factor")

      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to regenerate backup codes.")
        |> redirect(to: ~p"/account/two_factor")
    end
  end

  defp assign_user(conn, _opts) do
    assign(conn, :user, conn.assigns.current_user)
  end

  defp handle_avatar_upload(%{"avatar" => %Plug.Upload{} = upload} = user_params, user) do
    case Elektrine.Uploads.upload_avatar(upload, user.id) do
      {:ok, url} ->
        {Map.put(user_params, "avatar", url), nil}

      {:error, {error_type, message}} ->
        error_message = format_upload_error(error_type, message)
        {Map.delete(user_params, "avatar"), error_message}

      {:error, reason} ->
        {Map.delete(user_params, "avatar"), "Failed to upload avatar: #{inspect(reason)}"}
    end
  end

  defp handle_avatar_upload(user_params, _user), do: {user_params, nil}

  defp format_upload_error(error_type, message) do
    case error_type do
      :file_too_large -> "Avatar upload failed: #{message}"
      :empty_file -> "Avatar upload failed: #{message}"
      :invalid_file_type -> "Avatar upload failed: #{message}"
      :invalid_extension -> "Avatar upload failed: #{message}"
      :malicious_content -> "Avatar upload failed: File contains potentially unsafe content"
      :image_too_wide -> "Avatar upload failed: #{message}"
      :image_too_tall -> "Avatar upload failed: #{message}"
      :invalid_image -> "Avatar upload failed: Invalid image file"
      _ -> "Avatar upload failed: #{message}"
    end
  end
end
