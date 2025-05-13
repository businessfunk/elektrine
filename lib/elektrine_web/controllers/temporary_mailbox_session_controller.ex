defmodule ElektrineWeb.TemporaryMailboxSessionController do
  use ElektrineWeb, :controller

  @doc """
  Sets the temporary mailbox token in the session and redirects to the mailbox view.
  This is used by LiveView components that need to update session data.
  """
  def set_token(conn, %{"token" => token}) do
    conn
    |> put_session("temporary_mailbox_token", token)
    |> redirect(to: ~p"/temp-mail/#{token}")
  end
end