defmodule ElektrineWeb.Plugs.Auth do
  @moduledoc """
  Authentication plug for session-based authentication.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Elektrine.Accounts

  @doc """
  Initialize options for the plug.
  """
  def init(opts), do: opts

  @doc """
  A function plug that fetches the current user from the session and assigns it
  to the connection if a user is logged in.
  """
  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    cond do
      # User is already assigned (e.g., by another plug)
      conn.assigns[:current_user] ->
        conn

      user = user_id && Accounts.get_user!(user_id) ->
        assign(conn, :current_user, user)

      true ->
        assign(conn, :current_user, nil)
    end
  end

  @doc """
  A function plug that ensures the user is authenticated.
  """
  def authenticate_user(conn, _opts) do
    if conn.assigns.current_user do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  @doc """
  Logs in a user by setting the session data.
  """
  def login(conn, user) do
    conn
    |> assign(:current_user, user)
    |> put_session(:user_id, user.id)
    |> configure_session(renew: true)
  end

  @doc """
  Logs out a user by dropping the session data.
  """
  def logout(conn) do
    conn
    |> configure_session(drop: true)
  end
end
