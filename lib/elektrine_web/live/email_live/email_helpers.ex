defmodule ElektrineWeb.EmailLive.EmailHelpers do
  @moduledoc """
  Helper functions for working with emails in the LiveView components.
  """
  use Phoenix.Component
  import ElektrineWeb.CoreComponents

  # Routes generation with the ~p sigil
  use Phoenix.VerifiedRoutes,
    endpoint: ElektrineWeb.Endpoint,
    router: ElektrineWeb.Router,
    statics: ElektrineWeb.static_paths()

  def format_date(datetime) do
    case datetime do
      %DateTime{} ->
        Calendar.strftime(datetime, "%b %d, %Y %H:%M")

      _ ->
        ""
    end
  end

  def truncate(text, max_length \\ 50) do
    if String.length(text || "") > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  @doc """
  Generate a clean preview from email content, handling HTML and base64 encoding
  """
  def email_preview(message, max_length \\ 150) do
    cond do
      # Try HTML body first if available
      message.html_body && String.trim(message.html_body) != "" ->
        message.html_body
        |> ElektrineWeb.CoreComponents.process_email_html()
        |> strip_html_tags()
        |> clean_preview_text()
        |> truncate(max_length)

      # Fall back to text body
      message.text_body && String.trim(message.text_body) != "" ->
        message.text_body
        |> ElektrineWeb.CoreComponents.process_email_html()
        |> clean_preview_text()
        |> truncate(max_length)

      # Default fallback
      true ->
        "No preview available"
    end
  end

  defp strip_html_tags(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    # Remove HTML entities
    |> String.replace(~r/&\w+;/, " ")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp strip_html_tags(content), do: content || ""

  defp clean_preview_text(text) when is_binary(text) do
    text
    # Replace newlines with spaces
    |> String.replace(~r/\r?\n/, " ")
    # Replace tabs with spaces
    |> String.replace(~r/\t/, " ")
    # Normalize multiple spaces
    |> String.replace(~r/\s+/, " ")
    # Remove non-printable characters
    |> String.replace(~r/[^\x20-\x7E]/, "")
    |> String.trim()
  end

  defp clean_preview_text(content), do: content || ""

  def message_class(message) do
    if message.read do
      "bg-base-100 border-base-300"
    else
      "bg-gradient-to-r from-primary/5 to-primary/10 border-primary/20 shadow-sm"
    end
  end

  attr :mailbox, :map, required: true
  attr :unread_count, :integer, required: true
  attr :current_page, :string, required: true
  attr :current_user, :map, required: true

  def sidebar(assigns) do
    ~H"""
    <!-- Sidebar -->
    <div class="w-full lg:w-80">
      <!-- Mailbox Info Card -->
      <div class="card bg-gradient-to-br from-base-100 to-base-200 shadow-lg border border-base-300 mb-6 digital-frame">
        <div class="card-body p-6">
          <div class="flex items-center space-x-3">
            <%= if @current_user.avatar do %>
              <div class="avatar">
                <div class="w-12 rounded-full">
                  <img
                    src={@current_user.avatar}
                    alt={@current_user.username}
                    class="rounded-full object-cover"
                  />
                </div>
              </div>
            <% else %>
              <div class="avatar placeholder">
                <div class="bg-primary text-primary-content rounded-full w-12">
                  <span class="text-lg font-bold">
                    {String.first(@current_user.username) |> String.upcase()}
                  </span>
                </div>
              </div>
            <% end %>
            <div class="flex-1">
              <h2 class="font-bold text-lg">Your Mailbox</h2>
              <p class="text-sm text-base-content/70 font-mono break-all">{@mailbox.email}</p>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Navigation Menu -->
      <div class="card bg-base-100 shadow-lg border border-base-300 digital-frame">
        <div class="card-body p-3">
          <ul class="menu menu-lg bg-base-100 rounded-box">
            <li>
              <.link
                href={~p"/email/inbox"}
                class={if @current_page == "inbox", do: "active", else: "hover:bg-base-200"}
              >
                <.icon name="hero-inbox" class="h-5 w-5" /> Inbox
                <%= if @unread_count > 0 do %>
                  <div class="badge badge-sm badge-secondary animate-pulse">{@unread_count}</div>
                <% end %>
              </.link>
            </li>
            <li>
              <.link
                href={~p"/email/sent"}
                class={if @current_page == "sent", do: "active", else: "hover:bg-base-200"}
              >
                <.icon name="hero-paper-airplane" class="h-5 w-5" /> Sent
              </.link>
            </li>
            <li>
              <.link
                href={~p"/email/search"}
                class={if @current_page == "search", do: "active", else: "hover:bg-base-200"}
              >
                <.icon name="hero-magnifying-glass" class="h-5 w-5" /> Search
              </.link>
            </li>
            <li>
              <.link
                href={~p"/email/temp"}
                class={if @current_page == "temp", do: "active", else: "hover:bg-base-200"}
              >
                <.icon name="hero-clock" class="h-5 w-5" /> Temp Mail
              </.link>
            </li>
            <li>
              <.link
                href={~p"/email/spam"}
                class={if @current_page == "spam", do: "active", else: "hover:bg-base-200"}
              >
                <.icon name="hero-exclamation-triangle" class="h-5 w-5" /> Spam
              </.link>
            </li>
            <li>
              <.link
                href={~p"/email/archive"}
                class={if @current_page == "archive", do: "active", else: "hover:bg-base-200"}
              >
                <.icon name="hero-archive-box" class="h-5 w-5" /> Archive
              </.link>
            </li>
            <li>
              <.link
                href={~p"/email/contacts"}
                class={if @current_page == "contacts", do: "active", else: "hover:bg-base-200"}
              >
                <.icon name="hero-user-group" class="h-5 w-5" /> Contacts
              </.link>
            </li>
          </ul>
          
    <!-- Compose Button - Separate from menu -->
          <div class="mt-4">
            <.link
              href={~p"/email/compose"}
              class={
                if @current_page == "compose",
                  do: "btn btn-primary w-full gap-2 btn-active flex items-center justify-center",
                  else: "btn btn-primary w-full gap-2 flex items-center justify-center"
              }
            >
              <.icon name="hero-pencil-square" class="h-5 w-5" /> Compose
            </.link>
          </div>
          
    <!-- Keyboard Shortcuts Button -->
          <div class="mt-2">
            <button
              class="btn btn-ghost btn-sm w-full gap-2 flex items-center justify-center text-base-content/70 hover:text-base-content"
              onclick="window.showKeyboardShortcuts()"
              title="Keyboard shortcuts (Shift + /)"
            >
              <.icon name="hero-command-line" class="h-4 w-4" /> Shortcuts
              <kbd class="kbd kbd-xs ml-1">?</kbd>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Returns an appropriate icon name for a file type based on content type
  """
  def get_file_icon(content_type) when is_binary(content_type) do
    case String.downcase(content_type) do
      "image/" <> _ -> "hero-photo"
      "video/" <> _ -> "hero-play"
      "audio/" <> _ -> "hero-musical-note"
      "text/" <> _ -> "hero-document-text"
      "application/pdf" -> "hero-document"
      "application/zip" <> _ -> "hero-archive-box"
      "application/x-" <> _ -> "hero-archive-box"
      _ -> "hero-document"
    end
  end

  def get_file_icon(_), do: "hero-document"

  @doc """
  Formats file size in human readable format
  """
  def format_file_size(size) when is_integer(size) do
    cond do
      size >= 1024 * 1024 * 1024 -> "#{Float.round(size / (1024 * 1024 * 1024), 1)} GB"
      size >= 1024 * 1024 -> "#{Float.round(size / (1024 * 1024), 1)} MB"
      size >= 1024 -> "#{Float.round(size / 1024, 1)} KB"
      true -> "#{size} B"
    end
  end

  def format_file_size(_), do: "0 B"

  @doc """
  Extracts sender name from email address
  """
  def get_sender_name(from) when is_binary(from) do
    case Regex.run(~r/^(.+?)\s*<(.+)>$/, from) do
      [_, name, _email] -> String.trim(name, "\"")
      _ -> from
    end
  end

  def get_sender_name(_), do: "Unknown"

  @doc """
  Gets sender initials for avatar display
  """
  def get_sender_initials(from) when is_binary(from) do
    name = get_sender_name(from)

    case String.split(name, " ") do
      [first] ->
        String.slice(String.upcase(first), 0, 1)

      [first, last | _] ->
        String.slice(String.upcase(first), 0, 1) <> String.slice(String.upcase(last), 0, 1)

      _ ->
        "?"
    end
  end

  def get_sender_initials(_), do: "?"
end
