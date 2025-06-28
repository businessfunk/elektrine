defmodule ElektrineWeb.UserSessionController do
  use ElektrineWeb, :controller

  alias Elektrine.Accounts
  alias ElektrineWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  def create(conn, %{"user" => user_params}) do
    %{"username" => username, "password" => password} = user_params

    case Accounts.authenticate_user(username, password) do
      {:ok, user} ->
        if user.two_factor_enabled do
          conn
          |> UserAuth.store_user_for_two_factor_verification(user)
          |> redirect(to: ~p"/two_factor")
        else
          conn
          |> put_flash(:info, "Welcome back!")
          |> UserAuth.log_in_user(user, user_params)
        end

      {:error, :banned} ->
        conn
        |> put_flash(
          :error,
          "Your account has been banned. Please contact support if you believe this is an error."
        )
        |> render(:new, error_message: "Account banned")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid username or password")
        |> render(:new, error_message: "Invalid username or password")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
