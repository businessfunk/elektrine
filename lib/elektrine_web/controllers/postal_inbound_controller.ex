defmodule ElektrineWeb.PostalInboundController do
  use ElektrineWeb, :controller
  require Logger

  # IP addresses allowed to access this endpoint (Postal server IPs)
  @allowed_ips [
    # IPv4
    "64.176.192.218",
    # IPv6
    "2001:19f0:5:674b:5400:5ff:fe30:4723"
  ]

  # Authentication credentials
  @auth_username System.get_env("POSTAL_AUTH_USERNAME")
  @auth_password System.get_env("POSTAL_AUTH_PASSWORD")

  def create(conn, params) do
    start_time = System.monotonic_time(:millisecond)

    # Debug logging
    Logger.info("Received postal inbound email. Params: #{inspect(params)}")
    Logger.info("Headers: #{inspect(conn.req_headers)}")

    # Track request for rate limiting
    remote_ip = get_remote_ip(conn)
    Logger.info("Request from IP: #{remote_ip}")

    with :ok <- authenticate(conn),
         :ok <- verify_ip(conn),
         :ok <- validate_request_size(conn),
         :ok <- check_rate_limit(remote_ip) do
      try do
        # Check if this is the new JSON format or legacy Base64 format
        cond do
          # New JSON format - check for required fields
          Map.has_key?(params, "plain_body") or Map.has_key?(params, "html_body") ->
            # Process structured JSON email data
            case process_json_email(params) do
              {:ok, email} ->
                duration = System.monotonic_time(:millisecond) - start_time
                Logger.info("Successfully processed JSON email: #{email.message_id} (#{duration}ms)")

                conn
                |> put_status(:ok)
                |> json(%{
                  status: "success",
                  message_id: email.id,
                  processing_time_ms: duration
                })

              {:error, reason} ->
                duration = System.monotonic_time(:millisecond) - start_time
                Logger.warning("Failed to process JSON email: #{inspect(reason)} (#{duration}ms)")

                conn
                |> put_status(:unprocessable_entity)
                |> json(%{
                  error: "Failed to process email: #{inspect(reason)}",
                  processing_time_ms: duration
                })
            end

          # Legacy Base64 format
          Map.has_key?(params, "message") ->
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

            message =
              if padding_needed < 4,
                do: message <> String.duplicate("=", padding_needed),
                else: message

            Logger.info("Message length after normalization: #{String.length(message)}")
            Logger.debug("Message preview: #{String.slice(message, 0, 100)}...")

            decoded_result =
              case Base.decode64(message) do
                {:ok, decoded} ->
                  {:ok, decoded}

                :error ->
                  # Try aggressive cleaning as a fallback
                  Logger.warning("Initial Base64 decoding failed, trying aggressive cleaning...")
                  clean_message = String.replace(message, ~r/[^A-Za-z0-9+\/=]/, "")

                  # Add padding if needed
                  padding_needed = rem(4 - rem(String.length(clean_message), 4), 4)

                  padded_message =
                    if padding_needed < 4,
                      do: clean_message <> String.duplicate("=", padding_needed),
                      else: clean_message

                  Base.decode64(padded_message)
              end

            case decoded_result do
              {:ok, decoded_message} ->
                Logger.info(
                  "Successfully decoded message. Length: #{String.length(decoded_message)}"
                )

                # Process the raw email and create a message in the database
                case process_email(decoded_message, rcpt_to) do
                  {:ok, email} ->
                    duration = System.monotonic_time(:millisecond) - start_time
                    Logger.info("Successfully processed email: #{email.message_id} (#{duration}ms)")

                    conn
                    |> put_status(:ok)
                    |> json(%{
                      status: "success",
                      message_id: email.id,
                      processing_time_ms: duration
                    })

                  {:error, reason} ->
                    duration = System.monotonic_time(:millisecond) - start_time
                    Logger.warning("Failed to process email: #{inspect(reason)} (#{duration}ms)")

                    conn
                    |> put_status(:unprocessable_entity)
                    |> json(%{
                      error: "Failed to process email: #{inspect(reason)}",
                      processing_time_ms: duration
                    })
                end

              :error ->
                Logger.error("Base64 decoding error - even after aggressive cleaning")
                Logger.error("Raw message (truncated): #{String.slice(message, 0, 100)}...")
                debug_base64(message)
                conn |> put_status(:bad_request) |> json(%{error: "Invalid Base64 encoding"})
            end

          # Missing required parameters
          true ->
            Logger.warning(
              "Missing required parameters. Available params: #{inspect(Map.keys(params))}"
            )

            conn |> put_status(:bad_request) |> json(%{error: "Missing required parameters (message or plain_body/html_body)"})
        end
      rescue
        e ->
          Logger.error("Error processing email: #{inspect(e)}")
          Logger.error("Stack trace: #{Exception.format_stacktrace()}")

          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Server error: #{inspect(e)}"})
      end
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Unauthorized"})

      {:error, :request_too_large} ->
        conn |> put_status(:payload_too_large) |> json(%{error: "Request too large"})

      {:error, :rate_limited} ->
        conn |> put_status(:too_many_requests) |> json(%{error: "Rate limited"})
    end
  end

  # Process decoded email message - made public for testing
  def process_email(raw_email, rcpt_to) do
    try do
      # Parse the email (using a library like Mail would be better but this is simple for now)
      # Handle different line endings
      normalized_email =
        if String.contains?(raw_email, "\r\n"),
          do: raw_email,
          else: String.replace(raw_email, "\n", "\r\n")

      # Split headers and body
      {headers, raw_body} =
        case String.split(normalized_email, "\r\n\r\n", parts: 2) do
          [headers, body] -> {headers, body}
          # Fall back if splitting fails
          _ -> {"", normalized_email}
        end

      # Extract text and HTML content separately
      text_body = extract_text_content(raw_body)
      html_body = extract_html(normalized_email)
      
      # For HTML-only emails, don't put HTML content in text_body
      content_type = extract_header(headers, "Content-Type") || ""
      is_html_email = String.contains?(String.downcase(content_type), "text/html")
      
      # If this is an HTML email and text_body contains HTML, clear text_body
      final_text_body = if is_html_email and html_body and String.contains?(text_body, "<") do
        nil  # Clear text_body for HTML-only emails
      else
        text_body
      end

      # Extract basic headers
      from =
        (extract_header(headers, "From") || mail_from_to_from(rcpt_to) || "unknown@example.com")
        |> decode_rfc2047_header()

      to =
        (extract_header(headers, "To") || rcpt_to || extract_header(headers, "Delivered-To") ||
           "unknown@elektrine.com")
        |> decode_rfc2047_header()

      subject = (extract_header(headers, "Subject") || "(No Subject)") |> decode_rfc2047_header()

      message_id =
        extract_header(headers, "Message-ID") || extract_header(headers, "Message-Id") ||
          "postal-#{:rand.uniform(1_000_000)}-#{System.system_time(:millisecond)}"

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
          Logger.info(
            "About to find_or_create_mailbox with to=#{inspect(to)}, rcpt_to=#{inspect(rcpt_to)}"
          )

          case find_or_create_mailbox(to, rcpt_to) do
            {:ok, mailbox} ->
              Logger.info(
                "Successfully found/created mailbox: #{mailbox.email} (id: #{mailbox.id}, user_id: #{mailbox.user_id})"
              )

              # Determine if this is a temporary mailbox from its structure
              is_temporary =
                case mailbox do
                  %{temporary: true} -> true
                  _ -> false
                end

              # Extract and process attachments
              attachments = extract_attachments(normalized_email)
              has_attachments = attachments != %{}

              # Store in database
              email_data = %{
                message_id: message_id,
                from: from,
                to: to,
                subject: subject,
                text_body: final_text_body,
                html_body: html_body,
                attachments: attachments,
                has_attachments: has_attachments,
                mailbox_id: mailbox.id,
                mailbox_type: if(is_temporary, do: "temporary", else: "regular"),
                status: "received",
                metadata: %{
                  raw_email: raw_email,
                  parsed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
                  temporary: is_temporary,
                  attachment_count: map_size(attachments)
                }
              }

              # Log that we're about to process the email
              Logger.info(
                "Processing email for mailbox:#{mailbox.id}" <>
                  if(mailbox.user_id, do: " (user:#{mailbox.user_id})", else: "")
              )

              # Enhanced deduplication check
              result =
                case find_duplicate_message(email_data) do
                  nil ->
                    # No duplicate found, create new message
                    Logger.info("Creating new message: #{email_data.message_id}")
                    Elektrine.Email.MailboxAdapter.create_message(email_data)

                  existing_message ->
                    # Duplicate found, return existing
                    Logger.info(
                      "Duplicate message detected: #{email_data.message_id} (existing: #{existing_message.id})"
                    )

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
              Logger.error(
                "FAILED to find or create mailbox for to=#{inspect(to)}, rcpt_to=#{inspect(rcpt_to)}"
              )

              Logger.error("Error reason: #{inspect(reason)}")
              Logger.error("This will result in 422 error being returned to Postal")
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

  # Process structured JSON email data
  def process_json_email(params) do
    try do
      # Extract email fields from JSON structure
      message_id = params["message_id"] || "postal-#{:rand.uniform(1_000_000)}-#{System.system_time(:millisecond)}"
      from = params["from"] || params["mail_from"] || "unknown@example.com"
      to = params["to"] || params["rcpt_to"] || "unknown@elektrine.com"
      subject = params["subject"] || "(No Subject)"
      text_body = params["plain_body"] || ""
      html_body = params["html_body"]
      
      # Process attachments from JSON format
      attachments = process_json_attachments(params["attachments"] || [])
      has_attachments = map_size(attachments) > 0

      Logger.info("Processing JSON email - From: #{from}, To: #{to}, Subject: #{subject}")
      Logger.info("Email has #{map_size(attachments)} attachments")

      # Check if this is actually an inbound email (TO elektrine.com addresses)
      from_clean = extract_clean_email(from) || ""
      to_clean = extract_clean_email(to) || ""
      Logger.info("Clean addresses - From: #{from_clean}, To: #{to_clean}")

      # Always log the check results for debugging
      is_outbound = is_outbound_email?(from, to)
      is_loopback = is_loopback_email?(from, to, subject)

      Logger.info("Email checks - Outbound: #{is_outbound}, Loopback: #{is_loopback}")

      if is_outbound do
        Logger.info("🚫 SKIPPING OUTBOUND JSON EMAIL from #{from} to #{to}")
        {:ok, %{id: "skipped-outbound", message_id: message_id}}
      else
        # Check if this is a recently sent email that's looping back
        if is_loopback do
          Logger.info("🔄 SKIPPING LOOPBACK JSON EMAIL from #{from} to #{to} - Subject: #{subject}")
          {:ok, %{id: "skipped-loopback", message_id: message_id}}
        else
          # Find or create the appropriate mailbox
          rcpt_to = params["rcpt_to"]
          Logger.info(
            "About to find_or_create_mailbox with to=#{inspect(to)}, rcpt_to=#{inspect(rcpt_to)}"
          )

          case find_or_create_mailbox(to, rcpt_to) do
            {:ok, mailbox} ->
              Logger.info(
                "Successfully found/created mailbox: #{mailbox.email} (id: #{mailbox.id}, user_id: #{mailbox.user_id})"
              )

              # Determine if this is a temporary mailbox from its structure
              is_temporary =
                case mailbox do
                  %{temporary: true} -> true
                  _ -> false
                end

              # Store in database
              email_data = %{
                message_id: message_id,
                from: from,
                to: to,
                subject: subject,
                text_body: text_body,
                html_body: html_body,
                attachments: attachments,
                has_attachments: has_attachments,
                mailbox_id: mailbox.id,
                mailbox_type: if(is_temporary, do: "temporary", else: "regular"),
                status: "received",
                metadata: %{
                  parsed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
                  temporary: is_temporary,
                  attachment_count: map_size(attachments),
                  format: "json",
                  postal_id: params["id"],
                  spam_status: params["spam_status"],
                  bounce: params["bounce"],
                  auto_submitted: params["auto_submitted"],
                  size: params["size"],
                  timestamp: params["timestamp"]
                }
              }

              # Log that we're about to process the email
              Logger.info(
                "Processing JSON email for mailbox:#{mailbox.id}" <>
                  if(mailbox.user_id, do: " (user:#{mailbox.user_id})", else: "")
              )

              # Enhanced deduplication check
              result =
                case find_duplicate_message(email_data) do
                  nil ->
                    # No duplicate found, create new message
                    Logger.info("Creating new JSON message: #{email_data.message_id}")
                    Elektrine.Email.MailboxAdapter.create_message(email_data)

                  existing_message ->
                    # Duplicate found, return existing
                    Logger.info(
                      "Duplicate JSON message detected: #{email_data.message_id} (existing: #{existing_message.id})"
                    )

                    {:ok, existing_message}
                end

              # Broadcast the actual message struct to user topic after creation
              case result do
                {:ok, message} ->
                  if mailbox.user_id do
                    Logger.info("Broadcasting created JSON message to user:#{mailbox.user_id}")

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
              Logger.error(
                "FAILED to find or create mailbox for to=#{inspect(to)}, rcpt_to=#{inspect(rcpt_to)}"
              )

              Logger.error("Error reason: #{inspect(reason)}")
              Logger.error("This will result in 422 error being returned to Postal")
              {:error, :no_mailbox}
          end
        end
      end
    rescue
      e ->
        Logger.error("Error processing JSON email: #{inspect(e)}")
        Logger.error("Stack trace: #{Exception.format_stacktrace()}")
        {:error, :parsing_error}
    end
  end

  # Process attachments from JSON format
  defp process_json_attachments(attachments) when is_list(attachments) do
    attachments
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {attachment, index}, acc ->
      case process_json_attachment(attachment, index) do
        nil -> acc
        processed_attachment -> Map.put(acc, "attachment_#{index}", processed_attachment)
      end
    end)
  end

  defp process_json_attachments(_), do: %{}

  # Process a single attachment from JSON format
  defp process_json_attachment(attachment, index) when is_map(attachment) do
    filename = attachment["filename"] || "attachment_#{index}"
    content_type = attachment["content_type"] || "application/octet-stream"
    size = attachment["size"] || 0
    data = attachment["data"] || ""

    # The data is already base64 encoded in the JSON format
    %{
      "filename" => filename,
      "content_type" => content_type,
      "encoding" => "base64",
      "data" => data,
      "size" => size
    }
  end

  defp process_json_attachment(_, _), do: nil

  # Simple header extraction
  defp extract_header(headers, header_name) do
    case Regex.run(~r/(?:^|\r\n|\n)#{header_name}:\s*([^\r\n]*)(?:\r\n|\n|$)/i, headers) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  # Extract HTML content from email body - robust modern email parser
  defp extract_html(email) do
    # Parse the email structure first
    parsed_email = parse_email_structure(email)
    
    # Find the best HTML content from parsed structure
    html_content = find_best_html_content(parsed_email)
    
    html_content || html_fallback(email)
  end

  # Parse email into structured format
  defp parse_email_structure(email) do
    # Split headers from body
    case String.split(email, ~r/\r?\n\r?\n/, parts: 2) do
      [headers, body] ->
        content_type = extract_header_value(headers, "content-type")
        
        if String.contains?(String.downcase(content_type || ""), "multipart") do
          parse_multipart_email(headers, body, content_type)
        else
          parse_simple_email(headers, body)
        end
      
      [_] ->
        # No clear header/body separation, treat as simple
        parse_simple_email(email, "")
    end
  end

  # Parse multipart email structure
  defp parse_multipart_email(headers, body, content_type) do
    boundary = extract_boundary(content_type, body)
    
    if boundary do
      parts = split_by_boundary(body, boundary)
      parsed_parts = Enum.map(parts, &parse_email_part/1)
      
      %{
        type: :multipart,
        headers: headers,
        boundary: boundary,
        parts: parsed_parts
      }
    else
      parse_simple_email(headers, body)
    end
  end

  # Parse simple (non-multipart) email
  defp parse_simple_email(headers, body) do
    content_type = extract_header_value(headers, "content-type")
    encoding = extract_header_value(headers, "content-transfer-encoding")
    
    %{
      type: :simple,
      headers: headers,
      content_type: content_type,
      encoding: encoding,
      body: body
    }
  end

  # Parse individual email part
  defp parse_email_part(part_content) do
    case String.split(part_content, ~r/\r?\n\r?\n/, parts: 2) do
      [part_headers, part_body] ->
        content_type = extract_header_value(part_headers, "content-type")
        encoding = extract_header_value(part_headers, "content-transfer-encoding")
        
        parsed_part = %{
          headers: part_headers,
          content_type: content_type,
          encoding: encoding,
          body: part_body
        }
        
        # Handle nested multipart
        if String.contains?(String.downcase(content_type || ""), "multipart") do
          boundary = extract_boundary(content_type, part_body)
          if boundary do
            nested_parts = split_by_boundary(part_body, boundary)
            Map.put(parsed_part, :nested_parts, Enum.map(nested_parts, &parse_email_part/1))
          else
            parsed_part
          end
        else
          parsed_part
        end
      
      [_] ->
        %{headers: "", content_type: nil, encoding: nil, body: part_content}
    end
  end

  # Find the best HTML content from parsed email structure
  defp find_best_html_content(parsed_email) do
    html_content = case parsed_email.type do
      :simple ->
        if is_html_content_type?(parsed_email.content_type) do
          decode_content(parsed_email.body, parsed_email.encoding)
        else
          nil
        end
      
      :multipart ->
        find_html_in_parts(parsed_email.parts)
    end
    
    # Clean and extract proper HTML body from the content
    if html_content do
      extract_clean_html_body(html_content)
    else
      nil
    end
  end

  # Extract clean HTML body content, removing MIME artifacts and standalone CSS
  defp extract_clean_html_body(html_content) do
    # First, try to find a complete HTML document
    case Regex.run(~r/<html[^>]*>.*?<\/html>/si, html_content) do
      [html_doc] ->
        clean_html_document(html_doc)
      
      _ ->
        # Try to find body content
        case Regex.run(~r/<body[^>]*>(.*?)<\/body>/si, html_content) do
          [_, body_content] ->
            "<html><head></head><body>#{clean_inline_content(body_content)}</body></html>"
          
          _ ->
            # No body tags, try to extract meaningful HTML content
            extract_meaningful_html(html_content)
        end
    end
  end

  # Clean a complete HTML document
  defp clean_html_document(html_doc) do
    html_doc
    |> remove_standalone_css()
    |> clean_mime_artifacts()
    |> normalize_whitespace()
  end

  # Clean inline content within body
  defp clean_inline_content(content) do
    content
    |> remove_standalone_css()
    |> clean_mime_artifacts()
    |> normalize_whitespace()
  end

  # Extract meaningful HTML from raw content
  defp extract_meaningful_html(content) do
    # Remove CSS blocks and MIME artifacts first
    cleaned = content
    |> remove_standalone_css()
    |> clean_mime_artifacts()
    |> String.trim()
    
    # Look for HTML-like content
    cond do
      # Contains HTML tags
      Regex.match?(~r/<[a-zA-Z][^>]*>/, cleaned) ->
        "<html><head></head><body>#{normalize_whitespace(cleaned)}</body></html>"
      
      # Plain text content
      String.length(cleaned) > 0 ->
        "<html><head></head><body><p>#{String.replace(cleaned, "\n", "<br>")}</p></body></html>"
      
      # Empty or invalid
      true ->
        nil
    end
  end

  # Remove standalone CSS blocks that appear outside of proper HTML structure
  defp remove_standalone_css(content) do
    content
    # Remove CSS that appears at the beginning (like the Facebook CSS)
    |> String.replace(~r/^[^<]*@media[^{]*\{[^}]*\}[^<]*/s, "")
    |> String.replace(~r/^[^<]*\.[^{]*\{[^}]*\}[^<]*/s, "")
    # Remove orphaned CSS rules with selectors like *[class]
    |> String.replace(~r/^[^<]*\*\[[^]]*\][^{]*\{[^}]*\}[^<]*/s, "")
    # Remove any remaining CSS blocks that appear before HTML tags
    |> remove_leading_css_blocks()
    |> String.trim()
  end

  # Remove CSS blocks that appear before any HTML content
  defp remove_leading_css_blocks(content) do
    # Split content to find where HTML actually starts
    case String.split(content, ~r/<[a-zA-Z]/, parts: 2) do
      [css_part, html_part] ->
        # If the first part contains CSS rules, remove them
        if String.contains?(css_part, "{") and String.contains?(css_part, "}") do
          "<" <> html_part
        else
          content
        end
      
      [_] ->
        # No HTML tags found, check if it's all CSS
        if String.contains?(content, "{") and String.contains?(content, "}") and not String.contains?(content, "<") do
          ""
        else
          content
        end
    end
  end

  # Clean MIME artifacts and headers
  defp clean_mime_artifacts(content) do
    content
    # Remove MIME boundary markers
    |> String.replace(~r/^--[^\r\n]+[\r\n]*/m, "")
    # Remove Content-Type headers that might be mixed in
    |> String.replace(~r/Content-Type:[^\r\n]*[\r\n]*/i, "")
    |> String.replace(~r/Content-Transfer-Encoding:[^\r\n]*[\r\n]*/i, "")
    |> String.replace(~r/Content-Disposition:[^\r\n]*[\r\n]*/i, "")
    # Remove other common MIME headers
    |> String.replace(~r/^[A-Za-z-]+:\s*[^\r\n]*[\r\n]*/m, "")
    |> String.trim()
  end

  # Normalize whitespace and line breaks
  defp normalize_whitespace(content) do
    content
    |> String.replace(~r/\r\n|\r|\n/, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # Find HTML content in email parts (prioritizes multipart/alternative)
  defp find_html_in_parts(parts) when is_list(parts) do
    # First, look for HTML in multipart/alternative containers
    alternative_html = 
      parts
      |> Enum.find(&is_multipart_alternative?/1)
      |> case do
        nil -> nil
        part -> find_html_in_nested_parts(part)
      end
    
    if alternative_html do
      alternative_html
    else
      # Fallback: find any HTML part
      parts
      |> Enum.find(&is_html_content_type?(&1.content_type))
      |> case do
        nil -> nil
        part -> decode_content(part.body, part.encoding)
      end
    end
  end

  # Find HTML in nested parts (for multipart/alternative)
  defp find_html_in_nested_parts(%{nested_parts: nested_parts}) when nested_parts != nil do
    nested_parts
    |> Enum.find(&is_html_content_type?(&1.content_type))
    |> case do
      nil -> nil
      part -> decode_content(part.body, part.encoding)
    end
  end
  
  defp find_html_in_nested_parts(_), do: nil

  # Extract boundary from Content-Type header or email body
  defp extract_boundary(content_type, body) do
    # Try Content-Type header first
    boundary = 
      case Regex.run(~r/boundary[=:]\s*"?([^"\r\n;]+)"?/i, content_type || "") do
        [_, boundary] -> String.trim(boundary, "\"")
        _ -> nil
      end
    
    # If not found, try to detect boundary patterns in body
    boundary || detect_boundary_in_body(body)
  end

  # Detect boundary patterns in email body
  defp detect_boundary_in_body(body) do
    cond do
      # Standard boundary patterns
      match = Regex.run(~r/^--([^\r\n]+)/m, body) ->
        case match do
          [_, boundary] -> String.trim(boundary)
          _ -> nil
        end
      
      # Microsoft/Exchange boundaries
      match = Regex.run(~r/------=_Part_[^_\r\n]+_[^\.\r\n]+\.\d+/m, body) ->
        case match do
          [boundary] -> String.trim_leading(boundary, "--")
          _ -> nil
        end
      
      # Apple Mail boundaries
      match = Regex.run(~r/--Apple-Mail=[A-F0-9-]+/m, body) ->
        case match do
          [boundary] -> String.trim_leading(boundary, "--")
          _ -> nil
        end
      
      true -> nil
    end
  end

  # Split email body by boundary markers
  defp split_by_boundary(body, boundary) do
    # Split by boundary, removing empty parts and boundary markers
    String.split(body, "--" <> boundary)
    |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(&1, "--")))
    |> Enum.map(&String.trim/1)
  end

  # Extract header value (case-insensitive)
  defp extract_header_value(headers, header_name) do
    case Regex.run(~r/^#{header_name}:\s*(.+?)$/mi, headers) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  # Check if content type is HTML
  defp is_html_content_type?(content_type) do
    content_type && String.contains?(String.downcase(content_type), "text/html")
  end

  # Check if content type is multipart/alternative
  defp is_multipart_alternative?(part) do
    part.content_type && String.contains?(String.downcase(part.content_type), "multipart/alternative")
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


  # Decode content based on encoding - enhanced for modern emails
  defp decode_content(content, encoding) when is_binary(content) do
    # Clean up content first
    clean_content = String.trim(content)
    
    case String.downcase(String.trim(encoding || "")) do
      "quoted-printable" ->
        decode_quoted_printable(clean_content)

      "base64" ->
        decode_base64_content(clean_content)
      
      "7bit" ->
        clean_content
      
      "8bit" ->
        clean_content
      
      "binary" ->
        clean_content
      
      # Handle encoding specified in different formats
      enc when enc in ["qp", "q"] ->
        decode_quoted_printable(clean_content)
      
      enc when enc in ["b64", "b"] ->
        decode_base64_content(clean_content)
      
      _ ->
        # Try to auto-detect encoding if not specified
        auto_decode_content(clean_content)
    end
  end

  defp decode_content(content, _), do: content

  # Enhanced Base64 decoding with fallback
  defp decode_base64_content(content) do
    # Remove any whitespace/newlines that might be in base64 content
    clean_base64 = String.replace(content, ~r/\s/, "")
    
    case Base.decode64(clean_base64) do
      {:ok, decoded} -> 
        # Check if decoded content is valid UTF-8
        if String.valid?(decoded) do
          decoded
        else
          # Fallback for invalid UTF-8: try to clean it up
          clean_invalid_utf8(decoded, content)
        end
      
      :error -> 
        # Try with padding
        padded = pad_base64(clean_base64)
        case Base.decode64(padded) do
          {:ok, decoded} -> decoded
          :error -> content
        end
    end
  end

  # Auto-detect and decode content
  defp auto_decode_content(content) do
    cond do
      # Looks like base64 (only alphanumeric + / + = characters)
      Regex.match?(~r/^[A-Za-z0-9+\/]+=*$/, String.replace(content, ~r/\s/, "")) ->
        decode_base64_content(content)
      
      # Looks like quoted-printable (has = followed by hex)
      Regex.match?(~r/=[0-9A-Fa-f]{2}/, content) ->
        decode_quoted_printable(content)
      
      # Check for HTML entities that need decoding
      String.contains?(content, "&") ->
        decode_html_entities(content)
      
      true ->
        content
    end
  end

  # Add padding to base64 string if needed
  defp pad_base64(str) do
    case rem(String.length(str), 4) do
      0 -> str
      1 -> str <> "==="
      2 -> str <> "=="
      3 -> str <> "="
    end
  end

  # Clean invalid UTF-8 characters
  defp clean_invalid_utf8(decoded, fallback) do
    try do
      # Try to replace invalid bytes with replacement character
      String.replace(decoded, ~r/[\x80-\xFF]+/, "?")
    rescue
      _ -> fallback
    end
  end

  # Decode HTML entities
  defp decode_html_entities(content) do
    content
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
    # Decode numeric entities
    |> String.replace(~r/&#(\d+);/, fn match ->
      case Regex.run(~r/&#(\d+);/, match) do
        [_, num_str] ->
          case Integer.parse(num_str) do
            {num, ""} when num <= 1114111 -> <<num::utf8>>
            _ -> match
          end
        _ -> match
      end
    end)
    # Decode hex entities
    |> String.replace(~r/&#x([0-9A-Fa-f]+);/, fn match ->
      case Regex.run(~r/&#x([0-9A-Fa-f]+);/, match) do
        [_, hex_str] ->
          case Integer.parse(hex_str, 16) do
            {num, ""} when num <= 1114111 -> <<num::utf8>>
            _ -> match
          end
        _ -> match
      end
    end)
  end

  # Decode quoted-printable encoding
  defp decode_quoted_printable(content) when is_binary(content) do
    content
    # Remove soft line breaks
    |> String.replace(~r/=\r?\n/, "")
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
            "Q" ->
              decode_quoted_printable(encoded_text |> String.replace("_", " "))

            "B" ->
              case Base.decode64(encoded_text) do
                {:ok, decoded} -> decoded
                :error -> match
              end

            _ ->
              match
          end

        _ ->
          match
      end
    end)
    |> String.trim()
  end

  defp decode_rfc2047_header(header), do: header

  # Extract attachments from email
  defp extract_attachments(email) do
    cond do
      # Check if this is a multipart message
      Regex.match?(~r/Content-Type:\s*multipart\//i, email) ->
        extract_multipart_attachments(email)

      # Single attachment (not multipart)
      Regex.match?(~r/Content-Disposition:\s*attachment/i, email) ->
        extract_single_attachment(email)

      true ->
        %{}
    end
  end

  defp extract_multipart_attachments(email) do
    # Find the boundary
    boundary =
      case Regex.run(~r/boundary="?([^"\r\n;]+)"?/i, email) do
        [_, boundary] -> boundary
        _ -> nil
      end

    if boundary do
      # Split by boundary and process each part
      parts = String.split(email, "--#{boundary}")

      parts
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {part, index}, acc ->
        case extract_attachment_from_part(part, index) do
          nil -> acc
          attachment -> Map.put(acc, "attachment_#{index}", attachment)
        end
      end)
    else
      %{}
    end
  end

  defp extract_single_attachment(email) do
    case extract_attachment_from_part(email, 0) do
      nil -> %{}
      attachment -> %{"attachment_0" => attachment}
    end
  end

  defp extract_attachment_from_part(part, index) do
    # Check if this part is an attachment
    if Regex.match?(~r/Content-Disposition:\s*attachment/i, part) do
      # Extract filename
      filename =
        case Regex.run(~r/filename="?([^"\r\n;]+)"?/i, part) do
          [_, name] -> name
          _ -> "attachment_#{index}"
        end

      # Extract content type
      content_type =
        case Regex.run(~r/Content-Type:\s*([^;\r\n]+)/i, part) do
          [_, type] -> String.trim(type)
          _ -> "application/octet-stream"
        end

      # Extract encoding
      encoding =
        case Regex.run(~r/Content-Transfer-Encoding:\s*([^\r\n]+)/i, part) do
          [_, enc] -> String.trim(enc)
          _ -> nil
        end

      # Extract content (after double newline)
      content =
        case Regex.run(~r/\r?\n\r?\n(.*)/s, part) do
          [_, data] -> String.trim(data)
          _ -> ""
        end

      # Decode content based on encoding
      decoded_content =
        case String.downcase(encoding || "") do
          "base64" ->
            case Base.decode64(content) do
              # Re-encode for storage
              {:ok, decoded} -> Base.encode64(decoded)
              :error -> content
            end

          _ ->
            content
        end

      %{
        "filename" => filename,
        "content_type" => content_type,
        "encoding" => encoding,
        "data" => decoded_content,
        "size" => byte_size(decoded_content)
      }
    else
      nil
    end
  end

  # Extract plain text content from email body
  defp extract_text_content(body) do
    text_content =
      cond do
        # Check if this is a multipart message
        Regex.match?(~r/Content-Type:\s*multipart\//i, body) ->
          # Find the boundary string
          boundary =
            case Regex.run(~r/boundary="?([^"\r\n;]+)"?/i, body) do
              [_, boundary] -> boundary
              _ -> nil
            end

          if boundary do
            # Try to find a text/plain part
            case Regex.run(
                   ~r/--#{Regex.escape(boundary)}.*?Content-Type:\s*text\/plain.*?(?:\r\n\r\n|\n\n)(.*?)(?:--#{Regex.escape(boundary)}|$)/si,
                   body
                 ) do
              [_, content] ->
                # Check for encoding and decode
                encoding = extract_header_value(body, "content-transfer-encoding")
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
              encoding =
                case Regex.run(~r/Content-Transfer-Encoding:\s*([^\r\n]+)/i, body) do
                  [_, enc] -> String.trim(enc)
                  _ -> nil
                end

              decode_content(content, encoding)

            _ ->
              body
          end

        # Just plain text without MIME headers
        true ->
          body
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

    Logger.info(
      "find_or_create_mailbox called with - To: #{inspect(to)}, RCPT_TO: #{inspect(rcpt_to)}"
    )

    Logger.info("Extracted clean email: #{inspect(clean_email)}")

    if clean_email do
      # First check if this email is an alias
      case Elektrine.Email.resolve_alias(clean_email) do
        target_email when is_binary(target_email) ->
          Logger.info("Email #{clean_email} is an alias, forwarding to #{target_email}")
          # Forward the email to the target address
          forward_email_to_alias(clean_email, target_email, to, rcpt_to)

        :no_forward ->
          Logger.info(
            "Email #{clean_email} is an alias without forwarding, delivering to main mailbox"
          )

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
                  Logger.info(
                    "Mailbox #{clean_email} has forwarding enabled, forwarding to #{target_email}"
                  )

                  forward_email_to_alias(clean_email, target_email, to, rcpt_to)

                nil ->
                  # No forwarding, use the mailbox normally
                  Logger.info(
                    "Found existing mailbox for email: #{clean_email} (id: #{mailbox.id})"
                  )

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
                  Logger.info(
                    "Creating orphaned mailbox for email: #{clean_email}: #{inspect(reason)}"
                  )

                  create_orphaned_mailbox(clean_email)
              end
          end
      end
    else
      Logger.warning(
        "Could not extract clean email from To: #{inspect(to)} or RCPT_TO: #{inspect(rcpt_to)}"
      )

      # Try to create a fallback email address
      fallback_email =
        case {to, rcpt_to} do
          {to_val, _} when is_binary(to_val) and to_val != "" ->
            # Try to use the to field as-is if it looks like an email
            if String.contains?(to_val, "@") do
              String.trim(to_val)
            else
              nil
            end

          {_, rcpt_val} when is_binary(rcpt_val) and rcpt_val != "" ->
            # Try to use rcpt_to as-is if it looks like an email
            if String.contains?(rcpt_val, "@") do
              String.trim(rcpt_val)
            else
              nil
            end

          _ ->
            nil
        end

      if fallback_email do
        Logger.info("Using fallback email: #{fallback_email}")
        # Try to find or create with fallback email
        case _find_existing_mailbox(fallback_email, fallback_email) do
          {:ok, mailbox} ->
            Logger.info("Found existing mailbox with fallback email")
            {:ok, mailbox}

          nil ->
            Logger.info("Creating orphaned mailbox with fallback email: #{fallback_email}")
            create_orphaned_mailbox(fallback_email)
        end
      else
        Logger.error(
          "No valid email address found in To: #{inspect(to)} or RCPT_TO: #{inspect(rcpt_to)}"
        )

        {:error, :invalid_email}
      end
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
        # Try exact match
        # Try case-insensitive match
        # Try local-part match
        regular_mailbox =
          Mailbox |> where(email: ^clean_email) |> Repo.one() ||
            Mailbox
            |> where([m], fragment("lower(?)", m.email) == ^String.downcase(clean_email))
            |> Repo.one() ||
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
  defp extract_clean_email(""), do: nil

  defp extract_clean_email(email) when is_binary(email) do
    # Clean up the input
    email = String.trim(email)

    # Try these patterns in sequence
    result =
      cond do
        # Pattern 1: Email in angle brackets <email@domain.com>
        Regex.match?(~r/<([^@>]+@[^>]+)>/, email) ->
          case Regex.run(~r/<([^@>]+@[^>]+)>/, email) do
            [_, clean] -> String.trim(clean)
            _ -> nil
          end

        # Pattern 2: Name <email@domain.com> format
        Regex.match?(~r/.+<([^@>]+@[^>]+)>/, email) ->
          case Regex.run(~r/.+<([^@>]+@[^>]+)>/, email) do
            [_, clean] -> String.trim(clean)
            _ -> nil
          end

        # Pattern 3: Simple email without spaces
        Regex.match?(~r/^[^\s<>]+@[^\s<>]+$/, email) ->
          String.trim(email)

        # Pattern 4: Find any email-like pattern
        Regex.match?(~r/([^\s<>,"']+@[^\s<>,"']+)/, email) ->
          case Regex.run(~r/([^\s<>,"']+@[^\s<>,"']+)/, email) do
            [_, clean] -> String.trim(clean)
            _ -> nil
          end

        # Pattern 5: Very loose pattern - anything with @ that looks email-ish
        String.contains?(email, "@") ->
          case Regex.run(~r/([^@\s]+@[^@\s]+)/, email) do
            [_, clean] -> String.trim(clean)
            _ -> nil
          end

        true ->
          nil
      end

    # Validate the result
    case result do
      nil ->
        nil

      clean when is_binary(clean) ->
        # Basic email validation
        if String.match?(clean, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/) do
          String.downcase(clean)
        else
          Logger.debug("Extracted email '#{clean}' failed validation")
          nil
        end
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
    sender_mailbox =
      Mailbox
      |> where([m], fragment("lower(?)", m.email) == ^String.downcase(from_clean))
      |> Repo.one()

    recipient_mailbox =
      Mailbox
      |> where([m], fragment("lower(?)", m.email) == ^String.downcase(to_clean))
      |> Repo.one()

    Logger.info(
      "Mailboxes - Sender: #{inspect(sender_mailbox && sender_mailbox.id)}, Recipient: #{inspect(recipient_mailbox && recipient_mailbox.id)}"
    )

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

        recent_sent =
          Message
          |> where([m], m.mailbox_id == ^sender_mailbox.id)
          |> where([m], m.status == "sent")
          |> where([m], m.to == ^to or m.to == ^to_clean or ilike(m.to, ^"%#{to_clean}%"))
          |> where([m], m.subject == ^subject)
          |> where([m], m.inserted_at > ^ten_minutes_ago)
          |> limit(1)
          |> Repo.one()

        if recent_sent do
          Logger.info(
            "Found recently sent email matching this inbound email: #{inspect(recent_sent.id)}"
          )

          Logger.info("Sent email - To: #{recent_sent.to}, Subject: #{recent_sent.subject}")
          true
        else
          # Log why we didn't find a match
          recent_count =
            Message
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
        supported_domains =
          Application.get_env(:elektrine, :email)[:supported_domains] || ["elektrine.com"]

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

      _ ->
        nil
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
      positions =
        Enum.take(
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

  # Get remote IP with proxy header support
  defp get_remote_ip(conn) do
    real_ip = List.first(Plug.Conn.get_req_header(conn, "x-real-ip"))
    forwarded_for = List.first(Plug.Conn.get_req_header(conn, "x-forwarded-for"))
    remote_ip = conn.remote_ip |> Tuple.to_list() |> Enum.join(".")

    real_ip ||
      if(forwarded_for, do: hd(String.split(forwarded_for, ",")) |> String.trim(), else: nil) ||
      remote_ip
  end

  # Validate request size to prevent DoS
  defp validate_request_size(conn) do
    content_length =
      case List.first(Plug.Conn.get_req_header(conn, "content-length")) do
        nil -> 0
        length_str -> String.to_integer(length_str)
      end

    # 50MB limit
    max_size = 50 * 1024 * 1024

    if content_length > max_size do
      Logger.warning("Request too large: #{content_length} bytes (max: #{max_size})")
      {:error, :request_too_large}
    else
      :ok
    end
  end

  # Simple rate limiting (in production, use Redis or proper rate limiter)
  defp check_rate_limit(ip) do
    # For now, just log - implement proper rate limiting in production
    Logger.debug("Rate limit check for IP: #{ip}")
    :ok
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
      incoming_ip =
        real_ip ||
          if(forwarded_for, do: hd(String.split(forwarded_for, ",")) |> String.trim(), else: nil) ||
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
  defp forward_email_to_alias(alias_email, target_email, _original_to, _original_rcpt_to) do
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

            {:error, _reason} ->
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

  # Enhanced duplicate message detection
  defp find_duplicate_message(email_data) do
    import Ecto.Query
    alias Elektrine.Email.Message
    alias Elektrine.Repo

    # Check by message ID first
    by_message_id =
      Message
      |> where(
        [m],
        m.message_id == ^email_data.message_id and m.mailbox_id == ^email_data.mailbox_id
      )
      |> Repo.one()

    if by_message_id do
      by_message_id
    else
      # Check for near-duplicates by subject, from, and time
      five_minutes_ago = DateTime.utc_now() |> DateTime.add(-300, :second)

      Message
      |> where([m], m.mailbox_id == ^email_data.mailbox_id)
      |> where([m], m.subject == ^email_data.subject)
      |> where([m], m.from == ^email_data.from)
      |> where([m], m.inserted_at > ^five_minutes_ago)
      |> limit(1)
      |> Repo.one()
    end
  end

  # Find the main mailbox for an alias that doesn't have forwarding
  defp find_main_mailbox_for_alias(alias_email) do
    alias Elektrine.Email

    # Get the alias to find the user
    case Email.get_alias_by_email(alias_email) do
      %Email.Alias{user_id: user_id} when is_integer(user_id) ->
        # Find the user's main mailbox
        case Email.get_user_mailbox(user_id) do
          %Email.Mailbox{} = mailbox ->
            Logger.info(
              "Found main mailbox for alias #{alias_email} (user_id: #{user_id}, mailbox_id: #{mailbox.id})"
            )

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
