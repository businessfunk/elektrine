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
    require Logger
    Logger.debug("Using remote IP for hCaptcha: #{inspect(remote_ip)}")
    
    # Try without IP first, as remoteip is optional for hCaptcha
    case HCaptcha.verify(captcha_token, nil) do
      {:ok, :verified} ->
        case Accounts.create_user(user_params) do
          {:ok, user} ->
            conn
            |> put_flash(:info, "User created successfully.")
            |> UserAuth.log_in_user(user)

          {:error, %Ecto.Changeset{} = changeset} ->
            render(conn, :new, changeset: changeset)
        end

      {:error, reason} ->
        # Log the error for debugging
        require Logger
        Logger.error("hCaptcha verification failed: #{inspect(reason)}")
        
        changeset = 
          %User{}
          |> Accounts.change_user_registration(user_params)
          |> Ecto.Changeset.add_error(:captcha, "Please complete the captcha verification")
        
        render(conn, :new, changeset: changeset)
    end
  end

  def create(conn, %{"user" => user_params}) do
    # No captcha token provided
    changeset = 
      %User{}
      |> Accounts.change_user_registration(user_params)
      |> Ecto.Changeset.add_error(:captcha, "Please complete the captcha verification")
    
    render(conn, :new, changeset: changeset)
  end

  defp get_remote_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded_ips | _] ->
        # X-Forwarded-For can contain multiple IPs, take the first one
        forwarded_ips
        |> String.split(",")
        |> List.first()
        |> String.trim()
      
      [] ->
        # Convert tuple IP to string format
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
    end
  end
end