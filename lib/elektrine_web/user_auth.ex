defmodule ElektrineWeb.UserAuth do
  @moduledoc """
  Handles user authentication in the web layer.
  """
  use ElektrineWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Elektrine.Accounts

  # Make the remember me cookie valid for 60 days.
  # If you want to customize, set :elektrine, :user_remember_me_cookie_max_age
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_elektrine_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the OWASP guidelines
  for more information.

  It also sets a cookie with the user's ID.
  This is used to remember users when they return to the app.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Phoenix.Token.sign(conn, "user auth", user.id)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks.
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp put_token_in_session(conn, token) do
    put_session(conn, :user_token, token)
  end

  defp signed_in_path(_conn), do: ~p"/"

  @doc """
  Logs the user out.

  It clears all session data for safety. See the OWASP guidelines
  for more information on this.
  """
  def log_out_user(conn) do
    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && fetch_user_by_token(user_token)
    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  defp fetch_user_by_token(token) do
    case Phoenix.Token.verify(ElektrineWeb.Endpoint, "user auth", token, max_age: @max_age) do
      {:ok, user_id} -> Accounts.get_user!(user_id)
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Confirms if the current user is authenticated.
  Used as a plug to ensure authentication in controllers.
  """
  def require_authenticated_user(conn, _opts) do
    case conn.assigns[:current_user] do
      %{banned: true} ->
        conn
        |> put_flash(:error, "Your account has been banned. You have been logged out.")
        |> log_out_user()

      %{} = _user ->
        conn

      nil ->
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> maybe_store_return_to()
        |> redirect(to: ~p"/login")
        |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  @doc """
  Redirects already authenticated users.
  Used as a plug in login/registration pages to prevent authenticated users
  from accessing these pages.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Ensures the current user is an admin.
  Used as a plug to restrict admin-only routes.
  """
  def require_admin_user(conn, _opts) do
    case conn.assigns[:current_user] do
      %{is_admin: true} ->
        conn

      _ ->
        conn
        |> put_flash(:error, "You must be an admin to access this page.")
        |> redirect(to: ~p"/")
        |> halt()
    end
  end
end
