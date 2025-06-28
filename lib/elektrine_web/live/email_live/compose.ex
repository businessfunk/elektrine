defmodule ElektrineWeb.EmailLive.Compose do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers

  alias Elektrine.Email
  alias Elektrine.Email.Sender

  require Logger

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    unread_count = Email.unread_count(mailbox.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
    end

    # Handle prefilled form data from params
    form_data = build_form_data(params, mailbox)
    page_title = get_page_title(params)

    # Get original message if in reply/forward mode (with security check)
    original_message =
      case Map.get(params, "message_id") do
        nil -> 
          nil
        id -> 
          message = Email.get_message(id)
          # Only allow access to messages from user's own mailbox
          if message && message.mailbox_id == mailbox.id do
            message
          else
            nil
          end
      end

    {:ok,
     socket
     |> assign(:page_title, page_title)
     |> assign(:mailbox, mailbox)
     |> assign(:unread_count, unread_count)
     |> assign(:mode, Map.get(params, "mode", "compose"))
     |> assign(:original_message_id, Map.get(params, "message_id"))
     |> assign(:original_message, original_message)
     |> assign(:html_mode, false)
     |> assign(:form, to_form(form_data))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    form_data = build_form_data(params, socket.assigns.mailbox)
    page_title = get_page_title(params)

    # Get original message if in reply/forward mode (with security check)
    original_message =
      case Map.get(params, "message_id") do
        nil -> 
          nil
        id -> 
          message = Email.get_message(id)
          # Only allow access to messages from user's own mailbox
          if message && message.mailbox_id == socket.assigns.mailbox.id do
            message
          else
            nil
          end
      end

    {:noreply,
     socket
     |> assign(:page_title, page_title)
     |> assign(:mode, Map.get(params, "mode", "compose"))
     |> assign(:original_message_id, Map.get(params, "message_id"))
     |> assign(:original_message, original_message)
     |> assign(:form, to_form(form_data))}
  end

  @impl true
  def handle_event("clear_form", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :form,
       to_form(%{
         "to" => "",
         "cc" => "",
         "bcc" => "",
         "subject" => "",
         "body" => ""
       })
     )
     |> put_flash(:info, "Form cleared")}
  end

  @impl true
  def handle_event("toggle_html_mode", _params, socket) do
    html_mode = !Map.get(socket.assigns, :html_mode, false)
    {:noreply, assign(socket, :html_mode, html_mode)}
  end

  @impl true
  def handle_event("save", %{"email" => email_params}, socket) do
    user = socket.assigns.current_user
    mailbox = socket.assigns.mailbox
    html_mode = Map.get(socket.assigns, :html_mode, false)
    mode = socket.assigns.mode
    original_message = Map.get(socket.assigns, :original_message)

    # Handle reply/forward mode differently
    {text_body, html_body} =
      if mode in ["reply", "forward"] && email_params["new_message"] do
        new_message = email_params["new_message"]
        # This is the plain text quoted content
        quoted_text = email_params["body"]

        # For text body, combine new message with quoted content
        combined_text = new_message <> "\n" <> quoted_text

        # For HTML body, we need to properly format the quoted content
        combined_html =
          if original_message && original_message.html_body &&
               String.trim(original_message.html_body) != "" do
            # We have HTML content from the original message
            new_message_html =
              if html_mode do
                markdown_to_html(new_message)
              else
                format_html_body(new_message)
              end

            # Format the HTML quote/forward
            if mode == "reply" do
              date_str = format_date_for_quote(original_message.inserted_at)

              sender_text =
                if original_message.status == "sent", do: "you", else: original_message.from

              new_message_html <>
                """
                <br><br>
                <div style="color: #666; border-left: 2px solid #ccc; padding-left: 10px; margin-left: 5px;">
                  On #{date_str}, #{sender_text} wrote:<br>
                  #{original_message.html_body}
                </div>
                """
            else
              # Forward mode
              date_str = format_date_for_quote(original_message.inserted_at)

              new_message_html <>
                """
                <br><br>
                <div style="border: 1px solid #ccc; padding: 15px; margin: 10px 0; background-color: #f9f9f9;">
                  <div style="color: #666; margin-bottom: 10px;">
                    ---------- Forwarded message ----------<br>
                    <strong>From:</strong> #{original_message.from}<br>
                    <strong>To:</strong> #{original_message.to}<br>
                    <strong>Date:</strong> #{date_str}<br>
                    <strong>Subject:</strong> #{original_message.subject}
                  </div>
                  <div style="margin-top: 15px;">
                    #{original_message.html_body}
                  </div>
                </div>
                """
            end
          else
            # No HTML in original, just convert the combined text
            if html_mode do
              markdown_to_html(new_message) <> format_html_body(quoted_text)
            else
              format_html_body(combined_text)
            end
          end

        {combined_text, combined_html}
      else
        # Regular compose mode
        text = email_params["body"]

        html =
          if html_mode do
            markdown_to_html(text)
          else
            format_html_body(text)
          end

        {text, html}
      end

    case Sender.send_email(user.id, %{
           from: mailbox.email,
           to: email_params["to"],
           cc: email_params["cc"],
           bcc: email_params["bcc"],
           subject: email_params["subject"],
           text_body: text_body,
           html_body: html_body
         }) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> put_flash(:info, "Email sent successfully!")
         |> redirect(to: ~p"/email/sent")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to send email: #{inspect(reason)}")
         |> assign(:form, to_form(email_params))}
    end
  end


  defp get_or_create_mailbox(user) do
    case Email.get_user_mailbox(user.id) do
      nil ->
        {:ok, mailbox} = Email.ensure_user_has_mailbox(user)
        mailbox

      mailbox ->
        mailbox
    end
  end

  # Converts plain text to simple HTML
  defp format_html_body(nil), do: nil

  defp format_html_body(text) do
    paragraphs = String.split(text, "\n")

    # Simple manual HTML generation without dependency on Phoenix.HTML.Tag
    paragraphs
    |> Enum.map(fn line -> "<p>#{escape_html(line)}</p>" end)
    |> Enum.join("")
  end

  # Simple HTML escaping function to prevent XSS
  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  # Build form data based on parameters (reply/forward/compose)
  defp build_form_data(params, mailbox) do
    case {Map.get(params, "mode"), Map.get(params, "message_id")} do
      {"reply", message_id} when not is_nil(message_id) ->
        build_reply_data(message_id, mailbox)

      {"forward", message_id} when not is_nil(message_id) ->
        build_forward_data(message_id, mailbox)

      _ ->
        # Default compose form
        %{
          "to" => Map.get(params, "to", ""),
          "cc" => Map.get(params, "cc", ""),
          "bcc" => Map.get(params, "bcc", ""),
          "subject" => Map.get(params, "subject", ""),
          "body" => Map.get(params, "body", "")
        }
    end
  end

  defp build_reply_data(message_id, mailbox) do
    case Email.get_message(message_id) do
      nil ->
        %{"to" => "", "cc" => "", "bcc" => "", "subject" => "", "body" => ""}

      message ->
        # Security check: only allow reply to messages from user's own mailbox
        if message.mailbox_id != mailbox.id do
          %{"to" => "", "cc" => "", "bcc" => "", "subject" => "", "body" => ""}
        else
        subject =
          if String.starts_with?(message.subject, "Re: ") do
            message.subject
          else
            "Re: #{message.subject}"
          end

        # Format the quoted reply body
        quoted_body = format_quoted_reply(message)

        # For sent messages, reply to the recipient (to field)
        # For received messages, reply to the sender (from field)
        reply_to =
          if message.status == "sent" do
            extract_clean_email(message.to)
          else
            extract_clean_email(message.from)
          end

        %{
          "to" => reply_to,
          "cc" => "",
          "bcc" => "",
          "subject" => subject,
          "body" => quoted_body
        }
        end
    end
  end

  defp build_forward_data(message_id, mailbox) do
    case Email.get_message(message_id) do
      nil ->
        %{"to" => "", "cc" => "", "bcc" => "", "subject" => "", "body" => ""}

      message ->
        # Security check: only allow forward of messages from user's own mailbox
        if message.mailbox_id != mailbox.id do
          %{"to" => "", "cc" => "", "bcc" => "", "subject" => "", "body" => ""}
        else
        subject =
          if String.starts_with?(message.subject, "Fwd: ") do
            message.subject
          else
            "Fwd: #{message.subject}"
          end

        # Format the forwarded message body
        forwarded_body = format_forwarded_message(message)

        %{
          "to" => "",
          "cc" => "",
          "bcc" => "",
          "subject" => subject,
          "body" => forwarded_body
        }
        end
    end
  end

  defp format_quoted_reply(message) do
    date_str = format_date_for_quote(message.inserted_at)

    # For sent messages, show "you wrote" instead of the from address
    sender_text =
      if message.status == "sent" do
        "you"
      else
        message.from
      end

    # Always return plain text for the form field
    text_body = message.text_body || strip_html_tags(message.html_body || "")

    """


    On #{date_str}, #{sender_text} wrote:
    #{quote_message_body(text_body)}
    """
  end

  defp format_forwarded_message(message) do
    date_str = format_date_for_quote(message.inserted_at)

    # Always return plain text for the form field
    text_body = message.text_body || strip_html_tags(message.html_body || "")

    """


    ---------- Forwarded message ----------
    From: #{message.from}
    To: #{message.to}
    Date: #{date_str}
    Subject: #{message.subject}

    #{text_body}
    """
  end

  defp quote_message_body(body) do
    body
    |> String.split("\n")
    |> Enum.map(&"> #{&1}")
    |> Enum.join("\n")
  end

  defp format_date_for_quote(datetime) do
    case datetime do
      %DateTime{} ->
        Calendar.strftime(datetime, "%a, %b %d, %Y at %I:%M %p")

      _ ->
        ""
    end
  end

  defp get_page_title(params) do
    case Map.get(params, "mode") do
      "reply" -> "Reply to Message"
      "forward" -> "Forward Message"
      _ -> "Compose Email"
    end
  end


  defp strip_html_tags(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp markdown_to_html(markdown) do
    markdown
    # Headers
    |> String.replace(~r/^### (.*)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/^## (.*)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^# (.*)$/m, "<h1>\\1</h1>")
    # Bold
    |> String.replace(~r/\*\*(.*?)\*\*/s, "<strong>\\1</strong>")
    # Italic
    |> String.replace(~r/\*(.*?)\*/s, "<em>\\1</em>")
    # Links
    |> String.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, "<a href=\"\\2\">\\1</a>")
    # Lists (simple implementation)
    |> String.replace(~r/^- (.*)$/m, "<li>\\1</li>")
    # Quotes
    |> String.replace(~r/^> (.*)$/m, "<blockquote>\\1</blockquote>")
    # Line breaks
    |> String.replace("\n", "<br>")
  end

  # Extract clean email address from strings like "Display Name <email@domain.com>"
  defp extract_clean_email(nil), do: nil

  defp extract_clean_email(email) when is_binary(email) do
    # Handle multiple recipients by taking only the first one
    first_email =
      email
      |> String.split(",")
      |> List.first()
      |> String.trim()

    cond do
      # Handle "Display Name <email@domain.com>" format
      Regex.match?(~r/<([^@>]+@[^>]+)>/, first_email) ->
        [_, clean] = Regex.run(~r/<([^@>]+@[^>]+)>/, first_email)
        String.trim(clean)

      # Handle plain email addresses that might have whitespace
      Regex.match?(~r/([^\s<>]+@[^\s<>]+)/, first_email) ->
        [_, clean] = Regex.run(~r/([^\s<>]+@[^\s<>]+)/, first_email)
        String.trim(clean)

      # Return as-is if it looks like a plain email
      Regex.match?(~r/^[^\s]+@[^\s]+$/, first_email) ->
        String.trim(first_email)

      true ->
        # Fallback: return original if no patterns match
        String.trim(first_email)
    end
  end

  @impl true
  def handle_info({:unread_count_updated, new_count}, socket) do
    {:noreply, assign(socket, :unread_count, new_count)}
  end
end
