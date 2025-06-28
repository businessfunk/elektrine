defmodule ElektrineWeb.TwoFactorController do
  use ElektrineWeb, :controller

  alias Elektrine.Accounts
  alias ElektrineWeb.UserAuth

  def new(conn, _params) do
    user = UserAuth.get_user_for_two_factor_verification(conn)
    
    if user do
      render(conn, :new, error_message: nil)
    else
      conn
      |> put_flash(:error, "Two-factor authentication session expired. Please log in again.")
      |> redirect(to: ~p"/login")
    end
  end

  def create(conn, %{"two_factor" => %{"code" => code}}) do
    user = UserAuth.get_user_for_two_factor_verification(conn)
    
    if user do
      case Accounts.verify_two_factor_code(user, code) do
        {:ok, :totp} ->
          conn
          |> put_flash(:info, "Welcome back!")
          |> UserAuth.complete_two_factor_login(user)

        {:ok, :backup_code} ->
          remaining_count = length(user.two_factor_backup_codes || []) - 1
          
          conn
          |> put_flash(:info, "Welcome back! You have #{remaining_count} backup codes remaining.")
          |> UserAuth.complete_two_factor_login(user)

        {:error, :invalid_code} ->
          conn
          |> put_flash(:error, "Invalid authentication code. Please try again.")
          |> render(:new, error_message: "Invalid authentication code")

        {:error, _} ->
          conn
          |> put_flash(:error, "Authentication failed. Please try again.")
          |> render(:new, error_message: "Authentication failed")
      end
    else
      conn
      |> put_flash(:error, "Two-factor authentication session expired. Please log in again.")
      |> redirect(to: ~p"/login")
    end
  end
end