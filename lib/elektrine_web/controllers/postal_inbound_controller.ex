defmodule ElektrineWeb.PostalInboundController do
  use ElektrineWeb, :controller
  require Logger

  # IP addresses allowed to access this endpoint (Postal server IPs)
  @allowed_ips [
    "64.176.192.218",                      # IPv4
    "2001:19f0:5:674b:5400:5ff:fe30:4723"  # IPv6
  ]

  # Authentication credentials
  @auth_username System.get_env("POSTAL_AUTH_USERNAME")
  @auth_password System.get_env("POSTAL_AUTH_PASSWORD")

  def create(conn, params) do
    # Debug logging
    Logger.info("Received postal inbound email. Params: #{inspect(params)}")
    Logger.info("Headers: #{inspect(conn.req_headers)}")

    with :ok <- authenticate(conn),
         :ok <- verify_ip(conn) do

      # Check for required message parameter
      unless Map.has_key?(params, "message") do
        Logger.warning("Missing required message parameter. Available params: #{inspect(Map.keys(params))}")
        conn |> put_status(:bad_request) |> json(%{error: "Missing message parameter"})
      else
        try do
          # Get recipient information if available for later use
          rcpt_to = Map.get(params, "rcpt_to")
          mail_from = Map.get(params, "mail_from")
          if rcpt_to, do: Logger.info("Recipient (RCPT TO): #{rcpt_to}")
          if mail_from, do: Logger.info("Sender (MAIL FROM): #{mail_from}")

          # Process Base64 encoded message - using simpler approach based on the Rails example
          message = params["message"] |> to_string()

          # Remove all whitespace including newlines
          message = String.replace(message, ~r/[\s\r\n]/, "")

          # Convert URL-safe to standard Base64
          message = message |> String.replace("-", "+") |> String.replace("_", "/")

          # Add padding if needed
          padding_needed = rem(4 - rem(String.length(message), 4), 4)
          message = if padding_needed < 4, do: message <> String.duplicate("=", padding_needed), else: message

          Logger.info("Message length after normalization: #{String.length(message)}")
          Logger.debug("Message preview: #{String.slice(message, 0, 100)}...")

          decoded_result = case Base.decode64(message) do
            {:ok, decoded} -> {:ok, decoded}
            :error ->
              # Try aggressive cleaning as a fallback
              Logger.warning("Initial Base64 decoding failed, trying aggressive cleaning...")
              clean_message = String.replace(message, ~r/[^A-Za-z0-9+\/=]/, "")

              # Add padding if needed
              padding_needed = rem(4 - rem(String.length(clean_message), 4), 4)
              padded_message = if padding_needed < 4,
                do: clean_message <> String.duplicate("=", padding_needed),
                else: clean_message

              Base.decode64(padded_message)
          end

          case decoded_result do
            {:ok, decoded_message} ->
              Logger.info("Successfully decoded message. Length: #{String.length(decoded_message)}")

              # Process the raw email and create a message in the database
              case process_email(decoded_message, rcpt_to) do
                {:ok, email} ->
                  Logger.info("Successfully processed email: #{email.message_id}")
                  conn |> put_status(:ok) |> json(%{status: "success", message_id: email.id})

                {:error, reason} ->
                  Logger.warning("Failed to process email: #{inspect(reason)}")
                  conn |> put_status(:unprocessable_entity) |> json(%{error: "Failed to process email: #{inspect(reason)}"})
              end

            :error ->
              Logger.error("Base64 decoding error - even after aggressive cleaning")
              Logger.error("Raw message (truncated): #{String.slice(message, 0, 100)}...")
              debug_base64(message)
              conn |> put_status(:bad_request) |> json(%{error: "Invalid Base64 encoding"})
          end
        rescue
          e ->
            Logger.error("Error processing email: #{inspect(e)}")
            Logger.error("Stack trace: #{Exception.format_stacktrace()}")
            conn |> put_status(:internal_server_error) |> json(%{error: "Server error: #{inspect(e)}"})
        end
      end
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})
    end
  end

  # Process decoded email message
  defp process_email(raw_email, rcpt_to) do
    try do
      # Parse the email (using a library like Mail would be better but this is simple for now)
      # Handle different line endings
      normalized_email = if String.contains?(raw_email, "\r\n"), do: raw_email, else: String.replace(raw_email, "\n", "\r\n")

      # Split headers and body
      {headers, raw_body} = case String.split(normalized_email, "\r\n\r\n", parts: 2) do
        [headers, body] -> {headers, body}
        _ -> {"", normalized_email} # Fall back if splitting fails
      end

      # Extract the actual text content from multipart emails
      body = extract_text_content(raw_body)

      # Extract basic headers
      from = extract_header(headers, "From") || mail_from_to_from(rcpt_to) || "unknown@example.com"
      to = extract_header(headers, "To") || rcpt_to || extract_header(headers, "Delivered-To") || "unknown@elektrine.com"
      subject = extract_header(headers, "Subject") || "(No Subject)"
      message_id = extract_header(headers, "Message-ID") || extract_header(headers, "Message-Id") ||
                   "postal-#{:rand.uniform(1000000)}-#{System.system_time(:millisecond)}"

      Logger.info("Extracted email fields - From: #{from}, To: #{to}, Subject: #{subject}")

      # Find or create the appropriate mailbox
      case find_or_create_mailbox(to, rcpt_to) do
        {:ok, mailbox} ->
          Logger.info("Using mailbox: #{mailbox.email} (user_id: #{mailbox.user_id})")

          # Store in database
          email_data = %{
            message_id: message_id,
            from: from,
            to: to,
            subject: subject,
            text_body: body,
            html_body: extract_html(normalized_email),
            mailbox_id: mailbox.id,
            status: "received",
            metadata: %{
              raw_email: raw_email,
              parsed_at: DateTime.utc_now() |> DateTime.to_iso8601()
            }
          }

          # Notify connected clients if user exists
          if mailbox.user_id do
            Logger.info("Broadcasting :new_email event for user:#{mailbox.user_id}")

            # Broadcast updated email_data with read flag explicitly set to false
            email_data = Map.put(email_data, :read, false)

            # Broadcasting to the proper PubSub topic
            Phoenix.PubSub.broadcast!(
              Elektrine.PubSub,
              "user:#{mailbox.user_id}",
              {:new_email, email_data}
            )
          else
            Logger.warn("No user_id associated with mailbox #{mailbox.id}, not broadcasting")
          end

          # Check if this message already exists before creating
          case Elektrine.Email.get_message_by_id(email_data.message_id, mailbox.id) do
            nil ->
              # Message doesn't exist, create it
              Elektrine.Email.create_message(email_data)

            existing_message ->
              # Message already exists, return it
              Logger.info("Message with ID #{email_data.message_id} already exists, skipping creation")
              {:ok, existing_message}
          end

        {:error, reason} ->
          Logger.warning("Could not find or create mailbox: #{inspect(reason)}")
          {:error, :no_mailbox}
      end
    rescue
      e ->
        Logger.error("Error parsing email: #{inspect(e)}")
        Logger.error("Stack trace: #{Exception.format_stacktrace()}")
        {:error, :parsing_error}
    end
  end

  # Simple header extraction
  defp extract_header(headers, header_name) do
    case Regex.run(~r/(?:^|\r\n|\n)#{header_name}:\s*([^\r\n]*)(?:\r\n|\n|$)/i, headers) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  # Extract HTML content from email body
  defp extract_html(email) do
    cond do
      # Check if this is a multipart message
      Regex.match?(~r/Content-Type:\s*multipart\//i, email) ->
        # Find the boundary string
        boundary = case Regex.run(~r/boundary="?([^"\r\n;]+)"?/i, email) do
          [_, boundary] -> boundary
          _ -> nil
        end

        if boundary do
          # Try to find a text/html part
          case Regex.run(~r/--#{Regex.escape(boundary)}.*?Content-Type:\s*text\/html.*?(?:\r\n\r\n|\n\n)(.*?)(?:--#{Regex.escape(boundary)}|$)/si, email) do
            [_, content] -> content
            _ -> html_fallback(email)
          end
        else
          html_fallback(email)
        end

      # Direct text/html content
      Regex.match?(~r/Content-Type:.*text\/html/i, email) ->
        case Regex.run(~r/Content-Type:.*text\/html.*?(?:\r\n\r\n|\n\n)(.*?)(?:--.*?--|\z)/si, email) do
          [_, html] -> html
          _ -> html_fallback(email)
        end

      # Fallback
      true -> html_fallback(email)
    end
  end

  # Fallback for HTML extraction
  defp html_fallback(email) do
    # Look for HTML tags in body
    if Regex.match?(~r/<html.*?>.*<\/html>/si, email) do
      case Regex.run(~r/(<html.*?>.*<\/html>)/si, email) do
        [_, html] -> html
        _ -> nil
      end
    else
      nil
    end
  end

  # Extract plain text content from email body
  defp extract_text_content(body) do
    cond do
      # Check if this is a multipart message
      Regex.match?(~r/Content-Type:\s*multipart\//i, body) ->
        # Find the boundary string
        boundary = case Regex.run(~r/boundary="?([^"\r\n;]+)"?/i, body) do
          [_, boundary] -> boundary
          _ -> nil
        end

        if boundary do
          # Try to find a text/plain part
          case Regex.run(~r/--#{Regex.escape(boundary)}.*?Content-Type:\s*text\/plain.*?(?:\r\n\r\n|\n\n)(.*?)(?:--#{Regex.escape(boundary)}|$)/si, body) do
            [_, content] -> content
            _ ->
              # If we couldn't find a text/plain part, just return the body without the MIME headers
              body
          end
        else
          # No boundary found, return as is
          body
        end

      # Check for simple text/plain content
      Regex.match?(~r/Content-Type:\s*text\/plain/i, body) ->
        case Regex.run(~r/(?:\r\n\r\n|\n\n)(.*)/si, body) do
          [_, content] -> content
          _ -> body
        end

      # Just plain text without MIME headers
      true -> body
    end
  end

  # Attempt to extract a From address from MAIL FROM value
  defp mail_from_to_from(nil), do: nil
  defp mail_from_to_from(mail_from) when is_binary(mail_from) do
    case Regex.run(~r/([^\s<>]+@[^\s<>]+)/, mail_from) do
      [_, email] -> email
      _ -> nil
    end
  end

  # Find mailbox from email address or rcpt_to, create if needed
  defp find_or_create_mailbox(to, rcpt_to) do
    alias Elektrine.Email.Mailbox
    alias Elektrine.Repo
    import Ecto.Query

    # Try to extract clean email address
    clean_email = extract_clean_email(to) || extract_clean_email(rcpt_to)

    if clean_email do
      # Try to find existing mailbox
      mailbox = _find_existing_mailbox(to, rcpt_to)

      if mailbox do
        # Found existing mailbox
        {:ok, mailbox}
      else
        # Try to find or create user
        case find_or_create_user_for_email(clean_email) do
          {:ok, user} ->
            # Create mailbox for user
            Logger.info("Creating mailbox for email: #{clean_email} (user_id: #{user.id})")
            Elektrine.Email.create_mailbox(user)

          {:error, reason} ->
            # Create "orphaned" mailbox without user
            Logger.info("Creating orphaned mailbox for email: #{clean_email}: #{inspect(reason)}")
            create_orphaned_mailbox(clean_email)
        end
      end
    else
      {:error, :invalid_email}
    end
  end

  # Internal helper to find existing mailbox without creating
  defp _find_existing_mailbox(to, rcpt_to) do
    alias Elektrine.Email.Mailbox
    alias Elektrine.Repo
    import Ecto.Query

    # Try to extract clean email address
    clean_email = extract_clean_email(to) || extract_clean_email(rcpt_to)

    if clean_email do
      # Try exact match
      Mailbox |> where(email: ^clean_email) |> Repo.one() ||
      # Try case-insensitive match
      Mailbox |> where([m], fragment("lower(?)", m.email) == ^String.downcase(clean_email)) |> Repo.one() ||
      # Try local-part match
      find_by_local_part(clean_email)
    else
      nil
    end
  end

  # Create a mailbox without a user
  defp create_orphaned_mailbox(email) do
    alias Elektrine.Email.Mailbox
    alias Elektrine.Repo

    %Mailbox{}
    |> Mailbox.orphaned_changeset(%{email: email})
    |> Repo.insert()
  end

  # Find or create user for email
  defp find_or_create_user_for_email(email) do
    alias Elektrine.Accounts
    alias Elektrine.Repo
    import Ecto.Query

    # Extract local part as possible username
    case String.split(email, "@") do
      [local_part, _domain] ->
        # Try to find existing user by username
        user = Accounts.get_user_by_username(local_part)

        if user do
          # Found existing user
          {:ok, user}
        else
          # Don't automatically create users
          {:error, :user_not_found}
        end

      _ ->
        {:error, :invalid_email_format}
    end
  end

  # Extract clean email from string
  defp extract_clean_email(nil), do: nil
  defp extract_clean_email(email) when is_binary(email) do
    # Try these patterns in sequence
    cond do
      Regex.match?(~r/<([^@>]+@[^>]+)>/, email) ->
        [_, clean] = Regex.run(~r/<([^@>]+@[^>]+)>/, email)
        clean

      Regex.match?(~r/([^\s<>]+@[^\s<>]+)/, email) ->
        [_, clean] = Regex.run(~r/([^\s<>]+@[^\s<>]+)/, email)
        clean

      Regex.match?(~r/^[^\s]+@[^\s]+$/, email) ->
        email

      true -> nil
    end
  end

  # Find mailbox by local part of email
  defp find_by_local_part(email) do
    alias Elektrine.Email.Mailbox
    alias Elektrine.Repo
    import Ecto.Query

    case String.split(email, "@") do
      [local_part, _domain] ->
        # Get application domain
        _app_domain = Application.get_env(:elektrine, :postal)[:domain] || "elektrine.com"

        # Try to match by username
        Mailbox
        |> join(:inner, [m], u in assoc(m, :user))
        |> where([_, u], fragment("lower(?)", u.username) == ^String.downcase(local_part))
        |> preload([_, u], user: u)
        |> Repo.one()

      _ -> nil
    end
  end

  # Debug Base64 issues
  defp debug_base64(message) do
    Logger.info("Debugging Base64 issues:")

    # Check length
    remainder = rem(String.length(message), 4)
    if remainder != 0, do: Logger.info("- Length not multiple of 4 (remainder: #{remainder})")

    # Check for invalid chars
    invalid_chars = Regex.scan(~r/[^A-Za-z0-9+\/=]/, message) |> List.flatten() |> Enum.uniq()
    unless Enum.empty?(invalid_chars) do
      Logger.info("- Invalid chars: #{inspect(invalid_chars)}")

      # Show the positions of some of the invalid chars for debugging
      positions = Enum.take(
        Enum.with_index(String.graphemes(message))
        |> Enum.filter(fn {char, _} -> char in invalid_chars end),
        5
      )
      Logger.info("- First few invalid chars at positions: #{inspect(positions)}")
    end

    # Check for URL-safe encoding
    if String.contains?(message, "-") or String.contains?(message, "_") do
      Logger.info("- Contains URL-safe chars ('-' or '_')")
    end

    # Try with more aggressive cleaning
    clean_message = String.replace(message, ~r/[^A-Za-z0-9+\/=]/, "")
    case Base.decode64(clean_message) do
      {:ok, _} ->
        Logger.info("- Aggressive cleaning worked! Problem was invalid characters.")
      _ ->
        Logger.info("- Aggressive cleaning still failed. Possible padding or encoding issue.")
    end
  end

  # Authentication check
  defp authenticate(conn) do
    if @auth_username == nil || @auth_password == nil do
      # No auth configured, allow all
      :ok
    else
      case Plug.BasicAuth.parse_basic_auth(conn) do
        {username, password} ->
          if Plug.Crypto.secure_compare(username, @auth_username) &&
             Plug.Crypto.secure_compare(password, @auth_password) do
            :ok
          else
            {:error, :unauthorized}
          end
        _ ->
          {:error, :unauthorized}
      end
    end
  end

  # IP verification check
  defp verify_ip(conn) do
    # Always allow in development environment
    if Application.get_env(:elektrine, :env) == :dev || Mix.env() == :dev do
      :ok
    else
      remote_ip = conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
      forwarded_for = List.first(Plug.Conn.get_req_header(conn, "x-forwarded-for"))
      real_ip = List.first(Plug.Conn.get_req_header(conn, "x-real-ip"))

      # Check all possible IP sources
      incoming_ip = real_ip ||
                    (if forwarded_for, do: hd(String.split(forwarded_for, ",")) |> String.trim(), else: nil) ||
                    remote_ip

      # Check against allowed IPs
      if incoming_ip in @allowed_ips do
        :ok
      else
        Logger.warning("Unauthorized postal inbound access attempt from IP: #{incoming_ip}")
        {:error, :unauthorized}
      end
    end
  end
end
