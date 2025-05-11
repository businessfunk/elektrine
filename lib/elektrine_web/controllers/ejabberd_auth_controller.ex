defmodule ElektrineWeb.EjabberdAuthController do
  use ElektrineWeb, :controller
  alias Elektrine.Accounts

  def auth(conn, %{"user" => username, "server" => server, "password" => password}) do
    result = 
      case Accounts.authenticate_user(username, password) do
        {:ok, _user} -> true
        {:error, _reason} -> false
      end

    json(conn, %{result: result})
  end

  def isuser(conn, %{"user" => username, "server" => server}) do
    result = 
      case Accounts.get_user_by_username(username) do
        nil -> false
        _user -> true
      end

    json(conn, %{result: result})
  end

  def setpass(conn, %{"user" => username, "server" => server, "password" => password}) do
    result =
      case Accounts.get_user_by_username(username) do
        nil -> false
        user ->
          case Accounts.update_user_password(user, %{password: password, password_confirmation: password}) do
            {:ok, _updated_user} -> true
            {:error, _changeset} -> false
          end
      end

    json(conn, %{result: result})
  end
end