defmodule Mix.Tasks.Email.DebugRaw do
  use Mix.Task
  require Logger

  @shortdoc "Debug a raw encoded email from Postal"

  @moduledoc """
  Debug a raw Base64 encoded email from Postal.

  This task takes the raw Base64 encoded message from a file and attempts to decode and parse it
  to help diagnose issues with email processing.

  ## Usage

      mix email.debug_raw /path/to/raw_email.txt

  The file should contain only the Base64 encoded message as would be received from Postal.
  """

  def run([file_path]) do
    # Start the application
    Mix.shell().info("Starting the application...")
    Mix.Task.run("app.start")

    # Read the file
    Mix.shell().info("Reading file: #{file_path}")
    encoded_message = File.read!(file_path)

    # Debug the message
    debug_message(encoded_message)
  end

  def run(_) do
    Mix.shell().error("Usage: mix email.debug_raw /path/to/raw_email.txt")
  end

  defp debug_message(encoded_message) do
    alias ElektrineWeb.PostalInboundController

    Mix.shell().info("Got Base64 encoded message of length: #{String.length(encoded_message)}")
    Mix.shell().info("First 100 characters: #{String.slice(encoded_message, 0, 100)}...")

    # Step 1: Normalize the Base64 encoded message
    Mix.shell().info("\n[Step 1] Normalizing Base64 encoding...")
    normalized = normalize_base64(encoded_message)
    Mix.shell().info("Normalized message length: #{String.length(normalized)}")

    # Step 2: Decode the Base64 message
    Mix.shell().info("\n[Step 2] Decoding Base64 message...")
    case Base.decode64(normalized) do
      {:ok, decoded} ->
        Mix.shell().info("Successfully decoded message!")
        Mix.shell().info("Decoded length: #{String.length(decoded)}")
        Mix.shell().info("First 200 characters:\n#{String.slice(decoded, 0, 200)}...")

        # Step 3: Parse the email
        Mix.shell().info("\n[Step 3] Parsing email...")
        parse_email(decoded)

      :error ->
        Mix.shell().error("Failed to decode Base64 message")
        # Try to diagnose Base64 decoding issues
        diagnose_base64_issues(normalized)
    end
  end

  defp normalize_base64(message) do
    # Clean the message
    clean_message = message
      # Remove any whitespace
      |> String.replace(~r/\s/, "")
      # Remove "data:text/plain;base64," prefix if present
      |> String.replace(~r/^data:.*?;base64,/, "")
      # Remove quotes if the string is enclosed in them
      |> String.replace(~r/^["']|["']$/, "")

    # Convert URL-safe Base64 to standard Base64
    standard_message = clean_message
      |> String.replace("-", "+")
      |> String.replace("_", "/")

    # Add padding if needed
    padding_needed = rem(4 - rem(String.length(standard_message), 4), 4)
    if padding_needed < 4 do
      standard_message <> String.duplicate("=", padding_needed)
    else
      standard_message
    end
  end

  defp diagnose_base64_issues(message) do
    Mix.shell().info("\nDiagnosing Base64 decoding issues:")

    # Check for incorrect length
    length = String.length(message)
    remainder = rem(length, 4)
    if remainder != 0 do
      Mix.shell().error("- Base64 length is not a multiple of 4 (length: #{length}, remainder: #{remainder})")
      Mix.shell().info("  Try adding #{4 - remainder} padding '=' characters")
    end

    # Check for invalid characters
    invalid_chars = Regex.scan(~r/[^A-Za-z0-9+\/=]/, message) |> List.flatten() |> Enum.uniq()
    unless Enum.empty?(invalid_chars) do
      Mix.shell().error("- Found invalid Base64 characters: #{inspect(invalid_chars)}")
      Mix.shell().info("  Only A-Z, a-z, 0-9, +, /, and = are valid in standard Base64")
    end

    # Check for potential URL-safe Base64
    if String.contains?(message, "-") or String.contains?(message, "_") do
      Mix.shell().error("- Message contains URL-safe Base64 characters ('-' or '_')")
      Mix.shell().info("  These should be converted to '+' and '/' respectively")
    end

    # Try chunked decoding to find where the problem is
    Mix.shell().info("\nAttempting chunked decoding to locate the issue:")
    chunk_size = 100
    0..div(length, chunk_size)
    |> Enum.each(fn i ->
      start_pos = i * chunk_size
      end_pos = min(start_pos + chunk_size, length)
      chunk = String.slice(message, start_pos, chunk_size)

      # Ensure chunk length is multiple of 4 by adding padding
      padded_chunk = if rem(String.length(chunk), 4) != 0 do
        padding = 4 - rem(String.length(chunk), 4)
        chunk <> String.duplicate("=", padding)
      else
        chunk
      end

      case Base.decode64(padded_chunk) do
        {:ok, _} ->
          Mix.shell().info("  Chunk #{i+1} (positions #{start_pos}-#{end_pos}) decoded successfully")
        :error ->
          Mix.shell().error("  Chunk #{i+1} (positions #{start_pos}-#{end_pos}) failed to decode")
          Mix.shell().error("  Content: #{chunk}")
      end
    end)
  end

  defp parse_email(raw_email) do
    # Handle different line endings
    normalized_email = if String.contains?(raw_email, "\r\n") do
      raw_email
    else
      String.replace(raw_email, "\n", "\r\n")
    end

    # Extract headers and body from the raw email
    {headers, body} = cond do
      # Standard format with \r\n\r\n separator
      String.contains?(normalized_email, "\r\n\r\n") ->
        Mix.shell().info("Email contains standard separator")
        parts = String.split(normalized_email, "\r\n\r\n", parts: 2)
        {hd(parts), List.last(parts)}

      # Non-standard format with just \n\n separator
      String.contains?(raw_email, "\n\n") ->
        Mix.shell().info("Email contains Unix-style separator")
        parts = String.split(raw_email, "\n\n", parts: 2)
        {hd(parts), List.last(parts)}

      # No clear separator, try to identify headers
      true ->
        Mix.shell().warn("No clear header/body separator found, attempting to parse anyway")
        # Try to find where headers might end
        case Regex.run(~r/.*?(?:(?:\r\n|\n)[A-Za-z-]+:.*)+(?:\r\n|\n)/s, raw_email) do
          [headers_part] ->
            {headers_part, String.replace_prefix(raw_email, headers_part, "")}
          nil ->
            Mix.shell().warn("Could not identify headers, treating whole email as body")
            {"", raw_email}
        end
    end

    Mix.shell().info("Headers length: #{String.length(headers)}")
    Mix.shell().info("Body length: #{String.length(body)}")

    # Display key headers
    extract_and_display_header(headers, "From")
    extract_and_display_header(headers, "To")
    extract_and_display_header(headers, "Cc")
    extract_and_display_header(headers, "Subject")
    extract_and_display_header(headers, "Date")
    extract_and_display_header(headers, "Message-ID")
    extract_and_display_header(headers, "Content-Type")

    # Look for HTML content
    html_part = extract_html_part(normalized_email)
    if html_part do
      Mix.shell().info("HTML body found (#{String.length(html_part)} bytes)")
      Mix.shell().info("HTML preview: #{String.slice(html_part, 0, 100)}...")
    else
      Mix.shell().info("No HTML body found")
    end

    # Check for potential recipient mailbox
    to_header = extract_header(headers, "To") ||
               extract_header(headers, "Delivered-To") ||
               extract_header(headers, "X-Original-To")

    if to_header do
      Mix.shell().info("\nLooking up potential recipient mailbox...")
      clean_email = clean_email_address(to_header)
      Mix.shell().info("Cleaned email address: #{clean_email}")

      # Check if this email exists in our system
      check_mailbox_existence(clean_email)
    else
      Mix.shell().warn("No recipient email address found")
    end
  end

  defp extract_and_display_header(headers, header_name) do
    value = extract_header(headers, header_name)
    if value do
      Mix.shell().info("#{header_name}: #{value}")
    else
      Mix.shell().info("#{header_name}: <not found>")
    end
  end

  # Simple header extraction for debugging purposes
  defp extract_header(headers, header_name) do
    # Try different patterns to match header formats
    cond do
      # Standard header with possible continuation lines
      result = Regex.run(~r/#{header_name}:\s*(.+?)(\r\n(?![\w-]+:|\r\n).*?)*?(\r\n[\w-]+:|\r\n\r\n|\z)/s, headers) ->
        case result do
          [match, value | _] ->
            # Extract the entire matched value including continuation lines
            full_value = String.slice(headers, String.length(headers) - String.length(match), String.length(match))
            # Remove the header name and trailing delimiter
            full_value = String.replace(full_value, ~r/^#{header_name}:\s*/, "")
            full_value = String.replace(full_value, ~r/\r\n[\w-]+:.*$|\r\n\r\n.*$|\z.*$/s, "")
            # Normalize whitespace in continuation lines
            full_value = String.replace(full_value, ~r/\r\n\s+/, " ")
            String.trim(full_value)
          _ -> nil
        end

      # Simple header without continuation
      result = Regex.run(~r/#{header_name}:\s*([^\r\n]*)/i, headers) ->
        case result do
          [_, value] -> String.trim(value)
          _ -> nil
        end

      # Case-insensitive match for common headers
      result = Regex.run(~r/#{String.downcase(header_name)}:\s*([^\r\n]*)/i, headers) ->
        case result do
          [_, value] -> String.trim(value)
          _ -> nil
        end

      true -> nil
    end
  end

  # Extract HTML part from multipart email
  defp extract_html_part(raw_email) do
    # Try multiple patterns to extract HTML content
    cond do
      # Pattern 1: Standard multipart with boundary
      result = Regex.run(~r/Content-Type: text\/html.*?(\r\n\r\n|\n\n)(.*?)(\r\n--|\n--)/s, raw_email) ->
        case result do
          [_, _, content, _] -> content
          _ -> nil
        end

      # Pattern 2: HTML only email
      result = Regex.run(~r/Content-Type: text\/html.*?(\r\n\r\n|\n\n)(.*)/s, raw_email) ->
        case result do
          [_, _, content] -> content
          _ -> nil
        end

      # Pattern 3: Look for <html> tags in the body
      result = Regex.run(~r/(\r\n\r\n|\n\n).*?(<html>.*<\/html>)/s, raw_email) ->
        case result do
          [_, _, content] -> content
          _ -> nil
        end

      true -> nil
    end
  end

  # Clean an email address string
  defp clean_email_address(email) do
    cond do
      # Format: "Name <email@example.com>"
      result = Regex.run(~r/<([^>]+)>/, email) ->
        List.last(result)

      # Format: "email@example.com (Name)"
      result = Regex.run(~r/([^\s]+@[^\s(]+)/, email) ->
        List.last(result)

      # Just an email address
      Regex.match?(~r/^[^\s]+@[^\s]+$/, email) ->
        email

      true ->
        email
    end
  end

  # Check if an email address has a mailbox in our system
  defp check_mailbox_existence(email) do
    import Ecto.Query
    alias Elektrine.Email.Mailbox
    alias Elektrine.Repo

    # Try exact match first
    case Mailbox |> where(email: ^email) |> Repo.one() do
      nil ->
        Mix.shell().warn("No exact mailbox match found for #{email}")

        # Try to extract username and domain
        case String.split(email, "@") do
          [username, domain] ->
            Mix.shell().info("Extracted username: #{username}, domain: #{domain}")

            # Get application domain for comparison
            app_domain = Application.get_env(:elektrine, :postal)[:domain] || "elektrine.com"
            Mix.shell().info("Application email domain: #{app_domain}")

            if String.downcase(domain) == String.downcase(app_domain) do
              # Check for user with this username
              alias Elektrine.Accounts.User
              case User |> where(username: ^username) |> Repo.one() do
                nil ->
                  Mix.shell().warn("No user found with username: #{username}")
                user ->
                  Mix.shell().info("Found user: #{user.username} (ID: #{user.id})")
                  # Check for mailbox by user_id
                  case Mailbox |> where(user_id: ^user.id) |> Repo.one() do
                    nil ->
                      Mix.shell().warn("User exists but no mailbox found for user_id: #{user.id}")
                    mailbox ->
                      Mix.shell().info("Found mailbox: #{mailbox.email} (ID: #{mailbox.id})")
                  end
              end
            else
              Mix.shell().warn("Domain #{domain} doesn't match application domain #{app_domain}")
            end

          _ ->
            Mix.shell().warn("Could not split email into username and domain: #{email}")
        end

      mailbox ->
        Mix.shell().info("Found mailbox: #{mailbox.email} (ID: #{mailbox.id})")
    end
  end
end
