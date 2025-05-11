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
end