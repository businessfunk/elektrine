defmodule ElektrineWeb.ForgotPasswordController do
  use ElektrineWeb, :controller

  alias Elektrine.Accounts

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"user" => %{"recovery_email" => recovery_email}}) do
    if user = Accounts.get_user_by_recovery_email(recovery_email) do
      Accounts.deliver_user_reset_password_instructions(user)
    end

    # Always return success to prevent email enumeration attacks
    conn
    |> put_flash(:info, "If your email is in our system, you will receive password reset instructions shortly.")
    |> redirect(to: ~p"/")
  end
end 