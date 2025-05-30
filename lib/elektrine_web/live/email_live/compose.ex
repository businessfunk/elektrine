defmodule ElektrineWeb.EmailLive.Compose do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers

  alias Elektrine.Email
  alias Elektrine.Email.Sender

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    unread_count = Email.unread_count(mailbox.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
    end

    # Handle prefilled form data from params
    form_data = build_form_data(params)
    page_title = get_page_title(params)

    {:ok,
     socket
     |> assign(:page_title, page_title)
     |> assign(:mailbox, mailbox)
     |> assign(:unread_count, unread_count)
     |> assign(:mode, Map.get(params, "mode", "compose"))
     |> assign(:original_message_id, Map.get(params, "message_id"))
     |> assign(:html_mode, false)
     |> assign(:form, to_form(form_data))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    form_data = build_form_data(params)
    page_title = get_page_title(params)
    
    {:noreply,
     socket
     |> assign(:page_title, page_title)
     |> assign(:mode, Map.get(params, "mode", "compose"))
     |> assign(:original_message_id, Map.get(params, "message_id"))
     |> assign(:form, to_form(form_data))}
  end

  @impl true
  def handle_event("clear_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(%{
       "to" => "",
       "cc" => "",
       "bcc" => "",
       "subject" => "",
       "body" => ""
     }))
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

    html_body = if html_mode do
      markdown_to_html(email_params["body"])
    else
      format_html_body(email_params["body"])
    end

    case Sender.send_email(user.id, %{
      from: mailbox.email,
      to: email_params["to"],
      cc: email_params["cc"],
      bcc: email_params["bcc"],
      subject: email_params["subject"],
      text_body: email_params["body"],
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
  
  @impl true
  def handle_info({:new_email, _message}, socket) do
    mailbox = socket.assigns.mailbox
    
    {:noreply,
     socket
     |> assign(:unread_count, Email.unread_count(mailbox.id))}
  end

  defp get_or_create_mailbox(user) do
    case Email.get_user_mailbox(user.id) do
      nil -> 
        {:ok, mailbox} = Email.ensure_user_has_mailbox(user)
        mailbox
      mailbox -> mailbox
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
  defp build_form_data(params) do
    case {Map.get(params, "mode"), Map.get(params, "message_id")} do
      {"reply", message_id} when not is_nil(message_id) ->
        build_reply_data(message_id)
      
      {"forward", message_id} when not is_nil(message_id) ->
        build_forward_data(message_id)
      
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

  defp build_reply_data(message_id) do
    case Email.get_message(message_id) do
      nil ->
        %{"to" => "", "cc" => "", "bcc" => "", "subject" => "", "body" => ""}
      
      message ->
        subject = if String.starts_with?(message.subject, "Re: ") do
          message.subject
        else
          "Re: #{message.subject}"
        end
        
        # Format the quoted reply body
        quoted_body = format_quoted_reply(message)
        
        %{
          "to" => message.from,
          "cc" => "",
          "bcc" => "",
          "subject" => subject,
          "body" => quoted_body
        }
    end
  end

  defp build_forward_data(message_id) do
    case Email.get_message(message_id) do
      nil ->
        %{"to" => "", "cc" => "", "bcc" => "", "subject" => "", "body" => ""}
      
      message ->
        subject = if String.starts_with?(message.subject, "Fwd: ") do
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

  defp format_quoted_reply(message) do
    date_str = format_date_for_quote(message.inserted_at)
    
    """
    
    
    On #{date_str}, #{message.from} wrote:
    #{quote_message_body(message.text_body)}
    """
  end

  defp format_forwarded_message(message) do
    date_str = format_date_for_quote(message.inserted_at)
    
    """
    
    
    ---------- Forwarded message ----------
    From: #{message.from}
    To: #{message.to}
    Date: #{date_str}
    Subject: #{message.subject}
    
    #{message.text_body}
    """
  end

  defp quote_message_body(body) do
    body
    |> String.split("\n")
    |> Enum.map(&("> #{&1}"))
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

  defp build_email_metadata(mode, original_message_id) do
    case {mode, original_message_id} do
      {"reply", id} when not is_nil(id) ->
        %{"type" => "reply", "original_message_id" => id}
      
      {"forward", id} when not is_nil(id) ->
        %{"type" => "forward", "original_message_id" => id}
      
      _ ->
        %{"type" => "compose"}
    end
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

  @impl true
  def handle_info({:new_email, _message}, socket) do
    # Update unread count when new email arrives
    unread_count = Email.unread_count(socket.assigns.mailbox.id)
    {:noreply, assign(socket, :unread_count, unread_count)}
  end

  @impl true
  def handle_info({:unread_count_updated, new_count}, socket) do
    {:noreply, assign(socket, :unread_count, new_count)}
  end
end