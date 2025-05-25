defmodule ElektrineWeb.EmailLive.Compose do
  use ElektrineWeb, :live_view
  import ElektrineWeb.EmailLive.EmailHelpers

  alias Elektrine.Email
  alias Elektrine.Email.Sender

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    mailbox = get_or_create_mailbox(user)
    unread_count = Email.unread_count(mailbox.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Elektrine.PubSub, "user:#{user.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, "Compose Email")
     |> assign(:mailbox, mailbox)
     |> assign(:unread_count, unread_count)
     |> assign(:form, to_form(%{
       "to" => "",
       "cc" => "",
       "bcc" => "",
       "subject" => "",
       "body" => ""
     }))}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"email" => email_params}, socket) do
    user = socket.assigns.current_user
    mailbox = socket.assigns.mailbox

    case Sender.send_email(user.id, %{
      from: mailbox.email,
      to: email_params["to"],
      cc: email_params["cc"],
      bcc: email_params["bcc"],
      subject: email_params["subject"],
      text_body: email_params["body"],
      html_body: format_html_body(email_params["body"])
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
end