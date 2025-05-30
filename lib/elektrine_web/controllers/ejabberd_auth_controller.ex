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

  @doc """
  Get user avatar URL for ejabberd vCard support
  """
  def get_avatar(conn, %{"user" => username, "server" => _server}) do
    case Accounts.get_user_by_username(username) do
      nil ->
        json(conn, %{result: false})

      %{avatar: nil} ->
        json(conn, %{result: false})

      %{avatar: avatar} when avatar != "" ->
        avatar_url = Elektrine.Uploads.avatar_url(avatar)
        json(conn, %{result: true, avatar_url: avatar_url})

      _user ->
        json(conn, %{result: false})
    end
  end

  @doc """
  Get user profile information for ejabberd (includes avatar and display name)
  """
  def get_user_info(conn, %{"user" => username, "server" => _server}) do
    case Accounts.get_user_by_username(username) do
      nil ->
        json(conn, %{result: false})

      user ->
        avatar_url = if user.avatar && user.avatar != "" do
          Elektrine.Uploads.avatar_url(user.avatar)
        else
          nil
        end

        json(conn, %{
          result: true,
          email: user.email,
          avatar_url: avatar_url,
          display_name: user.email # or add a separate name field if you have one
        })
    end
  end
end