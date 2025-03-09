defmodule ElektrineWeb.SessionController do
  use ElektrineWeb, :controller

  alias Elektrine.Accounts
  alias ElektrineWeb.Plugs.Auth

  def new(conn, _params) do
    if conn.assigns.current_user do
      conn
      |> redirect(to: "/")
    else
      render(conn, :new, error_message: nil)
    end
  end

  def create(conn, %{"session" => %{"username_or_email" => username_or_email, "password" => password}}) do
    case Accounts.authenticate_user(username_or_email, password) do
      {:ok, user} ->
        conn
        |> Auth.login(user)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: "/")

      {:error, :bad_password} ->
        conn
        |> put_flash(:error, "Invalid password")
        |> render(:new, error_message: "Invalid password")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "User not found")
        |> render(:new, error_message: "User not found")
    end
  end

  def delete(conn, _params) do
    conn
    |> Auth.logout()
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: "/")
  end
end
