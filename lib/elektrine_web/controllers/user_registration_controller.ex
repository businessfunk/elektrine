defmodule ElektrineWeb.UserRegistrationController do
  use ElektrineWeb, :controller

  alias Elektrine.Accounts
  alias Elektrine.Accounts.User
  alias Elektrine.HCaptcha
  alias ElektrineWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    invite_codes_enabled = Elektrine.System.invite_codes_enabled?()
    render(conn, :new, changeset: changeset, invite_codes_enabled: invite_codes_enabled)
  end

  def create(conn, %{"user" => user_params, "h-captcha-response" => captcha_token}) do
    remote_ip = get_remote_ip(conn)
    require Logger
    Logger.debug("Using remote IP for hCaptcha: #{inspect(remote_ip)}")

    # Try without IP first, as remoteip is optional for hCaptcha
    case HCaptcha.verify(captcha_token, nil) do
      {:ok, :verified} ->
        # Check if invite codes are enabled
        if Elektrine.System.invite_codes_enabled?() do
          # Validate invite code
          invite_code = Map.get(user_params, "invite_code", "")
          
          case Accounts.validate_invite_code(invite_code) do
            {:ok, _invite_code} ->
              case Accounts.create_user(user_params) do
                {:ok, user} ->
                  # Use the invite code
                  Accounts.use_invite_code(invite_code, user.id)
                  
                  conn
                  |> put_flash(:info, "User created successfully.")
                  |> UserAuth.log_in_user(user)

                {:error, %Ecto.Changeset{} = changeset} ->
                  invite_codes_enabled = Elektrine.System.invite_codes_enabled?()
                  render(conn, :new, changeset: changeset, invite_codes_enabled: invite_codes_enabled)
              end
              
            {:error, reason} ->
              changeset =
                %User{}
                |> Accounts.change_user_registration(user_params)
                |> Ecto.Changeset.add_error(:invite_code, invite_code_error_message(reason))
              
              invite_codes_enabled = Elektrine.System.invite_codes_enabled?()
              render(conn, :new, changeset: changeset, invite_codes_enabled: invite_codes_enabled)
          end
        else
          # Invite codes disabled, proceed with normal registration
          case Accounts.create_user(user_params) do
            {:ok, user} ->
              conn
              |> put_flash(:info, "User created successfully.")
              |> UserAuth.log_in_user(user)

            {:error, %Ecto.Changeset{} = changeset} ->
              invite_codes_enabled = Elektrine.System.invite_codes_enabled?()
              render(conn, :new, changeset: changeset, invite_codes_enabled: invite_codes_enabled)
          end
        end

      {:error, reason} ->
        # Log the error for debugging
        require Logger
        Logger.error("hCaptcha verification failed: #{inspect(reason)}")

        changeset =
          %User{}
          |> Accounts.change_user_registration(user_params)
          |> Ecto.Changeset.add_error(:captcha, "Please complete the captcha verification")

        invite_codes_enabled = Elektrine.System.invite_codes_enabled?()
        render(conn, :new, changeset: changeset, invite_codes_enabled: invite_codes_enabled)
    end
  end

  def create(conn, %{"user" => user_params}) do
    # No captcha token provided
    changeset =
      %User{}
      |> Accounts.change_user_registration(user_params)
      |> Ecto.Changeset.add_error(:captcha, "Please complete the captcha verification")

    invite_codes_enabled = Elektrine.System.invite_codes_enabled?()
    render(conn, :new, changeset: changeset, invite_codes_enabled: invite_codes_enabled)
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
  
  defp invite_code_error_message(:invalid_code), do: "Invalid invite code"
  defp invite_code_error_message(:code_expired), do: "This invite code has expired"
  defp invite_code_error_message(:code_exhausted), do: "This invite code has reached its usage limit"
  defp invite_code_error_message(:code_inactive), do: "This invite code is no longer active"
  defp invite_code_error_message(_), do: "Invalid invite code"
end
