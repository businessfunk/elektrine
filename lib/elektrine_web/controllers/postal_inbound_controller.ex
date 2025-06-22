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

  # Process decoded email message - made public for testing
  def process_email(raw_email, rcpt_to) do
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
      from = (extract_header(headers, "From") || mail_from_to_from(rcpt_to) || "unknown@example.com") |> decode_rfc2047_header()
      to = (extract_header(headers, "To") || rcpt_to || extract_header(headers, "Delivered-To") || "unknown@elektrine.com") |> decode_rfc2047_header()
      subject = (extract_header(headers, "Subject") || "(No Subject)") |> decode_rfc2047_header()
      message_id = extract_header(headers, "Message-ID") || extract_header(headers, "Message-Id") ||
                   "postal-#{:rand.uniform(1000000)}-#{System.system_time(:millisecond)}"

      Logger.info("Extracted email fields - From: #{from}, To: #{to}, Subject: #{subject}")

      # Check if this is actually an inbound email (TO elektrine.com addresses)
      # Skip processing outbound emails (FROM elektrine.com TO external addresses)
      from_clean = extract_clean_email(from) || ""
      to_clean = extract_clean_email(to) || ""
      Logger.info("Clean addresses - From: #{from_clean}, To: #{to_clean}")
      
      # Always log the check results for debugging
      is_outbound = is_outbound_email?(from, to)
      is_loopback = is_loopback_email?(from, to, subject)
      
      Logger.info("Email checks - Outbound: #{is_outbound}, Loopback: #{is_loopback}")
      
      if is_outbound do
        Logger.info("🚫 SKIPPING OUTBOUND EMAIL from #{from} to #{to}")
        {:ok, %{id: "skipped-outbound", message_id: message_id}}
      else
        # Check if this is a recently sent email that's looping back
        if is_loopback do
          Logger.info("🔄 SKIPPING LOOPBACK EMAIL from #{from} to #{to} - Subject: #{subject}")
          {:ok, %{id: "skipped-loopback", message_id: message_id}}
        else
        # Find or create the appropriate mailbox
        case find_or_create_mailbox(to, rcpt_to) do
        {:ok, mailbox} ->
          Logger.info("Using mailbox: #{mailbox.email} (user_id: #{mailbox.user_id})")

          # Determine if this is a temporary mailbox from its structure
          is_temporary = case mailbox do
            %{temporary: true} -> true
            _ -> false
          end
          
          # Store in database
          email_data = %{
            message_id: message_id,
            from: from,
            to: to,
            subject: subject,
            text_body: body,
            html_body: extract_html(normalized_email),
            mailbox_id: mailbox.id,
            mailbox_type: if(is_temporary, do: "temporary", else: "regular"),
            status: "received",
            metadata: %{
              raw_email: raw_email,
              parsed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
              temporary: is_temporary
            }
          }

          # Log that we're about to process the email
          Logger.info("Processing email for mailbox:#{mailbox.id}" <> if(mailbox.user_id, do: " (user:#{mailbox.user_id})", else: ""))
          
          # Check if this message already exists before creating
          result = case Elektrine.Email.get_message_by_id(email_data.message_id, mailbox.id) do
            nil ->
              # Message doesn't exist, create it using the adapter
              Elektrine.Email.MailboxAdapter.create_message(email_data)

            existing_message ->
              # Message already exists, return it
              Logger.info("Message with ID #{email_data.message_id} already exists, skipping creation")
              {:ok, existing_message}
          end
          
          # Broadcast the actual message struct to user topic after creation
          case result do
            {:ok, message} ->
              if mailbox.user_id do
                Logger.info("Broadcasting created message to user:#{mailbox.user_id}")
                Phoenix.PubSub.broadcast!(
                  Elektrine.PubSub,
                  "user:#{mailbox.user_id}",
                  {:new_email, message}
                )
              end
              result
            error ->
              error
          end

        {:error, reason} ->
          Logger.warning("Could not find or create mailbox: #{inspect(reason)}")
          {:error, :no_mailbox}
      end
      end
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
    html_content = cond do
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
            [_, content] -> 
              # Check for encoding and decode
              encoding = extract_content_encoding(email, boundary, "text/html")
              decode_content(content, encoding)
            _ -> html_fallback(email)
          end
        else
          html_fallback(email)
        end

      # Direct text/html content
      Regex.match?(~r/Content-Type:.*text\/html/i, email) ->
        case Regex.run(~r/Content-Type:.*text\/html.*?(?:\r\n\r\n|\n\n)(.*?)(?:--.*?--|\z)/si, email) do
          [_, html] -> 
            # Check for encoding in the Content-Type header
            encoding = case Regex.run(~r/Content-Transfer-Encoding:\s*([^\r\n]+)/i, email) do
              [_, enc] -> String.trim(enc)
              _ -> nil
            end
            decode_content(html, encoding)
          _ -> html_fallback(email)
        end

      # Fallback
      true -> html_fallback(email)
    end

    html_content
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

  # Extract content encoding for a specific part in multipart email
  defp extract_content_encoding(email, boundary, content_type) do
    case Regex.run(~r/--#{Regex.escape(boundary)}.*?Content-Type:\s*#{content_type}.*?Content-Transfer-Encoding:\s*([^\r\n]+)/si, email) do
      [_, encoding] -> String.trim(encoding)
      _ -> nil
    end
  end

  # Decode content based on encoding
  defp decode_content(content, encoding) when is_binary(content) do
    case String.downcase(encoding || "") do
      "quoted-printable" ->
        decode_quoted_printable(content)
      
      "base64" ->
        case Base.decode64(content) do
          {:ok, decoded} -> decoded
          :error -> content
        end
      
      _ ->
        content
    end
  end

  defp decode_content(content, _), do: content

  # Decode quoted-printable encoding
  defp decode_quoted_printable(content) when is_binary(content) do
    content
    |> String.replace(~r/=\r?\n/, "")  # Remove soft line breaks
    |> String.replace(~r/=([0-9A-Fa-f]{2})/, fn match ->
      hex = String.slice(match, 1, 2)
      case Integer.parse(hex, 16) do
        {value, ""} -> <<value>>
        _ -> match
      end
    end)
  end

  # Decode RFC 2047 encoded headers (like subjects)
  defp decode_rfc2047_header(header) when is_binary(header) do
    # Pattern: =?charset?encoding?encoded-text?=
    header
    |> String.replace(~r/=\?([^?]+)\?([QqBb])\?([^?]*)\?=/, fn match ->
      case Regex.run(~r/=\?([^?]+)\?([QqBb])\?([^?]*)\?=/, match) do
        [_, _charset, encoding, encoded_text] ->
          case String.upcase(encoding) do
            "Q" -> decode_quoted_printable(encoded_text |> String.replace("_", " "))
            "B" -> 
              case Base.decode64(encoded_text) do
                {:ok, decoded} -> decoded
                :error -> match
              end
            _ -> match
          end
        _ -> match
      end
    end)
    |> String.trim()
  end

  defp decode_rfc2047_header(header), do: header

  # Extract plain text content from email body
  defp extract_text_content(body) do
    text_content = cond do
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
            [_, content] -> 
              # Check for encoding and decode
              encoding = extract_content_encoding(body, boundary, "text/plain")
              decode_content(content, encoding)
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
          [_, content] -> 
            # Check for encoding in the Content-Type header
            encoding = case Regex.run(~r/Content-Transfer-Encoding:\s*([^\r\n]+)/i, body) do
              [_, enc] -> String.trim(enc)
              _ -> nil
            end
            decode_content(content, encoding)
          _ -> body
        end

      # Just plain text without MIME headers
      true -> body
    end

    text_content
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
      # First check if this email is an alias
      case Elektrine.Email.resolve_alias(clean_email) do
        target_email when is_binary(target_email) ->
          Logger.info("Email #{clean_email} is an alias, forwarding to #{target_email}")
          # Forward the email to the target address
          forward_email_to_alias(clean_email, target_email, to, rcpt_to)
        
        :no_forward ->
          Logger.info("Email #{clean_email} is an alias without forwarding, delivering to main mailbox")
          # Alias exists but no forwarding, find the user's main mailbox
          find_main_mailbox_for_alias(clean_email)
        
        nil ->
          # Not an alias, proceed with normal mailbox lookup
          # Try to find existing mailbox (including temporary mailboxes)
          case _find_existing_mailbox(to, rcpt_to) do
            {:ok, mailbox} ->
              # Found existing mailbox, check if it has forwarding enabled
              case Elektrine.Email.get_mailbox_forward_target(mailbox) do
                target_email when is_binary(target_email) ->
                  Logger.info("Mailbox #{clean_email} has forwarding enabled, forwarding to #{target_email}")
                  forward_email_to_alias(clean_email, target_email, to, rcpt_to)
                
                nil ->
                  # No forwarding, use the mailbox normally
                  Logger.info("Found existing mailbox for email: #{clean_email} (id: #{mailbox.id})")
                  {:ok, mailbox}
              end
            
            nil ->
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
      # First check for temporary mailboxes
      temp_mailbox = Elektrine.Email.get_temporary_mailbox_by_email(clean_email)
      
      if temp_mailbox do
        Logger.info("Found temporary mailbox for email: #{clean_email} (id: #{temp_mailbox.id})")
        
        # Create a regular mailbox structure to be compatible with the rest of the code
        temp_mailbox_as_regular = %Mailbox{
          id: temp_mailbox.id,
          email: temp_mailbox.email,
          user_id: nil,
          temporary: true
        }
        
        {:ok, temp_mailbox_as_regular}
      else
        # No temporary mailbox found, check regular mailboxes
        regular_mailbox = 
          # Try exact match
          Mailbox |> where(email: ^clean_email) |> Repo.one() ||
          # Try case-insensitive match
          Mailbox |> where([m], fragment("lower(?)", m.email) == ^String.downcase(clean_email)) |> Repo.one() ||
          # Try local-part match
          find_by_local_part(clean_email)
          
        if regular_mailbox do
          {:ok, regular_mailbox}
        else
          nil
        end
      end
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

  # Check if this is an outbound email (FROM elektrine.com TO external addresses)
  defp is_outbound_email?(from, to) do
    from_clean = extract_clean_email(from) || ""
    to_clean = extract_clean_email(to) || ""
    
    # Check if FROM is elektrine.com and TO is external
    String.contains?(from_clean, "@elektrine.com") && 
    !String.contains?(to_clean, "@elektrine.com")
  end

  # Check if this is a loopback email (sent by a user that's coming back through inbound)
  defp is_loopback_email?(from, to, subject) do
    import Ecto.Query
    alias Elektrine.Email.Message
    alias Elektrine.Email.Mailbox
    alias Elektrine.Repo
    
    from_clean = extract_clean_email(from) || ""
    to_clean = extract_clean_email(to) || ""
    
    Logger.info("Loopback check - From: #{from_clean}, To: #{to_clean}, Subject: #{subject}")
    
    # Check if we have a mailbox for both the sender and recipient
    sender_mailbox = Mailbox
                     |> where([m], fragment("lower(?)", m.email) == ^String.downcase(from_clean))
                     |> Repo.one()
    
    recipient_mailbox = Mailbox
                        |> where([m], fragment("lower(?)", m.email) == ^String.downcase(to_clean))
                        |> Repo.one()
    
    Logger.info("Mailboxes - Sender: #{inspect(sender_mailbox && sender_mailbox.id)}, Recipient: #{inspect(recipient_mailbox && recipient_mailbox.id)}")
    
    cond do
      # First check if both mailboxes belong to the same user (user emailing themselves)
      sender_mailbox && recipient_mailbox && sender_mailbox.user_id && 
      sender_mailbox.user_id == recipient_mailbox.user_id ->
        Logger.info("Same user detected - User #{sender_mailbox.user_id} is emailing themselves")
        # For same-user emails, we only need the sent copy, not the received copy
        true
        
      # Check if we recently sent this email
      sender_mailbox && recipient_mailbox ->
        # Check if we recently sent this email (within last 10 minutes)
        ten_minutes_ago = DateTime.utc_now() |> DateTime.add(-600, :second)
        
        recent_sent = Message
                      |> where([m], m.mailbox_id == ^sender_mailbox.id)
                      |> where([m], m.status == "sent")
                      |> where([m], m.to == ^to or m.to == ^to_clean or ilike(m.to, ^("%#{to_clean}%")))
                      |> where([m], m.subject == ^subject)
                      |> where([m], m.inserted_at > ^ten_minutes_ago)
                      |> limit(1)
                      |> Repo.one()
        
        if recent_sent do
          Logger.info("Found recently sent email matching this inbound email: #{inspect(recent_sent.id)}")
          Logger.info("Sent email - To: #{recent_sent.to}, Subject: #{recent_sent.subject}")
          true
        else
          # Log why we didn't find a match
          recent_count = Message
                         |> where([m], m.mailbox_id == ^sender_mailbox.id)
                         |> where([m], m.status == "sent")
                         |> where([m], m.inserted_at > ^ten_minutes_ago)
                         |> select([m], %{id: m.id, to: m.to, subject: m.subject})
                         |> limit(5)
                         |> Repo.all()
          
          Logger.info("No loopback match found. Recent sent emails: #{inspect(recent_count)}")
          false
        end
        
      true ->
        Logger.info("Loopback check skipped - missing mailboxes")
        false
    end
  end

  # Find mailbox by local part of email
  defp find_by_local_part(email) do
    alias Elektrine.Email.Mailbox
    alias Elektrine.Repo
    import Ecto.Query

    case String.split(email, "@") do
      [local_part, domain] ->
        # Get supported domains
        supported_domains = Application.get_env(:elektrine, :email)[:supported_domains] || ["elektrine.com"]

        # Only proceed if the domain is supported
        if domain in supported_domains do
          # Try to match by username across all supported domains
          possible_emails = Enum.map(supported_domains, fn d -> "#{local_part}@#{d}" end)
          
          Mailbox
          |> where([m], m.email in ^possible_emails)
          |> preload([:user])
          |> Repo.one()
        else
          nil
        end

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
    if Application.get_env(:elektrine, :env) == :dev do
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

  # Forward email to alias target address
  defp forward_email_to_alias(alias_email, target_email, original_to, original_rcpt_to) do
    Logger.info("Forwarding email from alias #{alias_email} to #{target_email}")
    
    # Check if the target email is internal (within our domains)
    if is_internal_email?(target_email) do
      # Internal forwarding - find or create mailbox for target
      case _find_existing_mailbox(target_email, target_email) do
        {:ok, mailbox} ->
          Logger.info("Found internal mailbox for forwarding target: #{target_email}")
          {:ok, mailbox}
        
        nil ->
          # Try to find or create user for target email
          case find_or_create_user_for_email(target_email) do
            {:ok, user} ->
              Logger.info("Creating internal mailbox for forwarding target: #{target_email}")
              Elektrine.Email.create_mailbox(user)
            
            {:error, reason} ->
              Logger.info("Creating orphaned mailbox for forwarding target: #{target_email}")
              create_orphaned_mailbox(target_email)
          end
      end
    else
      # External forwarding - use Postal to forward the email
      Logger.info("External forwarding not yet implemented for #{target_email}")
      {:error, :external_forwarding_not_implemented}
    end
  end

  # Check if an email address belongs to our internal domains
  defp is_internal_email?(email) do
    email = String.downcase(email)
    String.contains?(email, "@elektrine.com") || String.contains?(email, "@z.org")
  end

  # Find the main mailbox for an alias that doesn't have forwarding
  defp find_main_mailbox_for_alias(alias_email) do
    alias Elektrine.Email
    alias Elektrine.Repo
    import Ecto.Query

    # Get the alias to find the user
    case Email.get_alias_by_email(alias_email) do
      %Email.Alias{user_id: user_id} when is_integer(user_id) ->
        # Find the user's main mailbox
        case Email.get_user_mailbox(user_id) do
          %Email.Mailbox{} = mailbox ->
            Logger.info("Found main mailbox for alias #{alias_email} (user_id: #{user_id}, mailbox_id: #{mailbox.id})")
            {:ok, mailbox}
          
          nil ->
            Logger.warning("No main mailbox found for user #{user_id} (alias: #{alias_email})")
            {:error, :no_main_mailbox}
        end
      
      nil ->
        Logger.warning("Alias #{alias_email} not found when looking for main mailbox")
        {:error, :alias_not_found}
    end
  end
end
