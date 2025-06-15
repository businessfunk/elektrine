defmodule ElektrineWeb.UserRegistrationController do
  use ElektrineWeb, :controller

  alias Elektrine.Accounts
  alias Elektrine.Accounts.User
  alias Elektrine.HCaptcha
  alias ElektrineWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params, "h-captcha-response" => captcha_token}) do
    remote_ip = get_remote_ip(conn)
    
    case HCaptcha.verify(captcha_token, remote_ip) do
      {:ok, :verified} ->
        case Accounts.create_user(user_params) do
          {:ok, user} ->
            conn
            |> put_flash(:info, "User created successfully.")
            |> UserAuth.log_in_user(user)

          {:error, %Ecto.Changeset{} = changeset} ->
            render(conn, :new, changeset: changeset)
        end

      {:error, _reason} ->
        changeset = 
          %User{}
          |> Accounts.change_user_registration(user_params)
          |> Ecto.Changeset.add_error(:captcha, "Please complete the captcha verification")
        
        render(conn, :new, changeset: changeset)
    end
  end

  def create(conn, %{"user" => user_params}) do
    changeset = 
      %User{}
      |> Accounts.change_user_registration(user_params)
      |> Ecto.Changeset.add_error(:captcha, "Please complete the captcha verification")
    
    render(conn, :new, changeset: changeset)
  end

  defp get_remote_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> to_string(:inet.ntoa(conn.remote_ip))
    end
  end
end