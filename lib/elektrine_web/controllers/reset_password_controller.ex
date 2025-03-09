defmodule ElektrineWeb.ResetPasswordController do
  use ElektrineWeb, :controller

  alias Elektrine.Accounts

  plug :get_user_by_reset_password_token when action in [:edit, :update]

  def new(conn, _params) do
    render(conn, :new)
  end

  def edit(conn, _params) do
    changeset = Accounts.change_user_password(conn.assigns.user)
    render(conn, :edit, changeset: changeset, token: conn.assigns.token)
  end

  def update(conn, %{"user" => user_params}) do
    case Accounts.reset_user_password(conn.assigns.user, user_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Password reset successfully.")
        |> redirect(to: ~p"/login")

      {:error, changeset} ->
        render(conn, :edit, changeset: changeset, token: conn.assigns.token)
    end
  end

  defp get_user_by_reset_password_token(conn, _opts) do
    %{"token" => token} = conn.params

    if user = Accounts.get_user_by_reset_password_token(token) do
      conn |> assign(:user, user) |> assign(:token, token)
    else
      conn
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end
end 