defmodule ElektrineWeb.UserSettingsController do
  use ElektrineWeb, :controller

  alias Elektrine.Accounts

  plug :assign_user

  def edit(conn, _params) do
    user = conn.assigns.current_user
    changeset = Accounts.change_user(user)
    render(conn, :edit, changeset: changeset)
  end

  def update(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user
    
    # Handle avatar upload if present
    user_params = handle_avatar_upload(user_params, user)

    case Accounts.update_user(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "User updated successfully.")
        |> redirect(to: ~p"/account")

      {:error, changeset} ->
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

  defp assign_user(conn, _opts) do
    assign(conn, :user, conn.assigns.current_user)
  end

  defp handle_avatar_upload(%{"avatar" => %Plug.Upload{} = upload} = user_params, user) do
    case Elektrine.Uploads.upload_avatar(upload, user.id) do
      {:ok, url} -> 
        Map.put(user_params, "avatar", url)
      {:error, _reason} -> 
        Map.delete(user_params, "avatar")
    end
  end
  
  defp handle_avatar_upload(user_params, _user), do: user_params
end