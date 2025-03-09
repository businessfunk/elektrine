defmodule ElektrineWeb.RegistrationController do
  use ElektrineWeb, :controller

  alias Elektrine.Accounts
  alias Elektrine.Accounts.User
  alias ElektrineWeb.Plugs.Auth

  def new(conn, _params) do
    if conn.assigns.current_user do
      conn
      |> redirect(to: "/")
    else
      changeset = Accounts.change_user_registration(%User{})
      render(conn, :new, changeset: changeset)
    end
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> Auth.login(user)
        |> put_flash(:info, "Account created successfully.")
        |> redirect(to: "/")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
