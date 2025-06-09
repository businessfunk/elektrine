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
                  <img src={@current_user.avatar} alt={@current_user.username} class="rounded-full object-cover" />
                </div>
              </div>
            <% else %>
              <div class="avatar placeholder">
                <div class="bg-primary text-primary-content rounded-full w-12">
                  <span class="text-lg font-bold"><%= String.first(@current_user.username) |> String.upcase() %></span>
                </div>
              </div>
            <% end %>
            <div class="flex-1">
              <h2 class="font-bold text-lg">Your Mailbox</h2>
              <p class="text-sm text-base-content/70 font-mono break-all"><%= @mailbox.email %></p>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Navigation Menu -->
      <div class="card bg-base-100 shadow-lg border border-base-300 digital-frame">
        <div class="card-body p-3">
          <ul class="menu menu-lg bg-base-100 rounded-box">
            <li>
              <.link href={~p"/email/inbox"} class={if @current_page == "inbox", do: "active", else: "hover:bg-base-200"}>
                <.icon name="hero-inbox" class="h-5 w-5" />
                Inbox
                <%= if @unread_count > 0 do %>
                  <div class="badge badge-sm badge-secondary animate-pulse"><%= @unread_count %></div>
                <% end %>
              </.link>
            </li>
            <li>
              <.link href={~p"/email/sent"} class={if @current_page == "sent", do: "active", else: "hover:bg-base-200"}>
                <.icon name="hero-paper-airplane" class="h-5 w-5" />
                Sent
              </.link>
            </li>
            <li>
              <.link href={~p"/email/temp"} class={if @current_page == "temp", do: "active", else: "hover:bg-base-200"}>
                <.icon name="hero-clock" class="h-5 w-5" />
                Temp Mail
              </.link>
            </li>
            <li>
              <.link href={~p"/email/spam"} class={if @current_page == "spam", do: "active", else: "hover:bg-base-200"}>
                <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
                Spam
              </.link>
            </li>
            <li>
              <.link href={~p"/email/archive"} class={if @current_page == "archive", do: "active", else: "hover:bg-base-200"}>
                <.icon name="hero-archive-box" class="h-5 w-5" />
                Archive
              </.link>
            </li>
            <li>
              <.link href={~p"/email/contacts"} class={if @current_page == "contacts", do: "active", else: "hover:bg-base-200"}>
                <.icon name="hero-user-group" class="h-5 w-5" />
                Contacts
              </.link>
            </li>
          </ul>
          
          <!-- Compose Button - Separate from menu -->
          <div class="mt-4">
            <.link href={~p"/email/compose"} class={if @current_page == "compose", do: "btn btn-primary w-full gap-2 btn-active flex items-center justify-center", else: "btn btn-primary w-full gap-2 flex items-center justify-center"}>
              <.icon name="hero-pencil-square" class="h-5 w-5" />
              Compose
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
end