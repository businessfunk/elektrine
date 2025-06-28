defmodule ElektrineWeb.Router do
  use ElektrineWeb, :router

  import ElektrineWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ElektrineWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Routes that don't require authentication
  scope "/", ElektrineWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/about", PageController, :about
    get "/contact", PageController, :contact
    post "/contact", PageController, :send_message

    # Temporary email LiveView routes
    live "/temp-mail", TemporaryMailboxLive.Index, :index
    live "/temp-mail/:token", TemporaryMailboxLive.Show, :show
    live "/temp-mail/:token/message/:id", TemporaryMailboxLive.Message, :show

    # Route for setting session data from LiveView
    get "/temp-mail/:token/set_token", TemporaryMailboxSessionController, :set_token

    # Temporary mailbox controller routes
    get "/temp-mail/:token/refresh", TemporaryMailboxController, :refresh
    post "/temp-mail/:token/extend", TemporaryMailboxController, :extend
    delete "/temp-mail/:token/message/:id/delete", TemporaryMailboxController, :delete_message
    get "/temp-mail/:token/message/:id/print", TemporaryMailboxController, :print
    get "/temp-mail/:token/message/:id/raw", TemporaryMailboxController, :raw
  end

  # Routes that are specifically for unauthenticated users
  scope "/", ElektrineWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/register", UserRegistrationController, :new
    post "/register", UserRegistrationController, :create
    get "/login", UserSessionController, :new
    post "/login", UserSessionController, :create
  end

  # Two-factor authentication routes (accessible during login process)
  scope "/", ElektrineWeb do
    pipe_through :browser

    get "/two_factor", TwoFactorController, :new
    post "/two_factor", TwoFactorController, :create
  end

  # Routes that require authentication
  scope "/", ElektrineWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/account", UserSettingsController, :edit
    put "/account", UserSettingsController, :update
    get "/account/password", UserSettingsController, :edit_password
    put "/account/password", UserSettingsController, :update_password
    get "/account/two_factor/setup", UserSettingsController, :two_factor_setup
    post "/account/two_factor/enable", UserSettingsController, :two_factor_enable
    get "/account/two_factor", UserSettingsController, :two_factor_manage
    post "/account/two_factor/disable", UserSettingsController, :two_factor_disable
    post "/account/two_factor/regenerate", UserSettingsController, :two_factor_regenerate_codes
    get "/account/delete", UserSettingsController, :delete
    delete "/account", UserSettingsController, :confirm_delete

    # Email LiveView routes - each is a separate LiveView with individual templates
    live_session :authenticated,
      on_mount: {ElektrineWeb.Live.AuthHooks, :require_authenticated_user} do
      live "/email", EmailLive.Index, :index
      live "/email/inbox", EmailLive.Inbox, :inbox
      live "/email/sent", EmailLive.Sent, :sent
      live "/email/spam", EmailLive.Spam, :spam
      live "/email/archive", EmailLive.Archive, :archive
      live "/email/compose", EmailLive.Compose, :new
      live "/email/view/:id", EmailLive.Show, :show
      live "/email/search", EmailLive.Search, :search
      live "/email/contacts", EmailLive.Contacts, :contacts
      live "/email/temp", EmailLive.TempMail, :index
      live "/email/temp/:token", EmailLive.TempMail, :show
      live "/email/temp/:token/message/:id", EmailLive.TempMail, :message
    end

    # Email controller routes
    delete "/email/:id", EmailController, :delete
    get "/email/:id/print", EmailController, :print
    get "/email/:id/raw", EmailController, :raw
    get "/email/:id/iframe", EmailController, :iframe_content

    # Mailbox management
    get "/mailboxes", MailboxController, :index
    get "/mailboxes/new", MailboxController, :new
    post "/mailboxes", MailboxController, :create
    delete "/mailboxes/:id", MailboxController, :delete
    put "/mailboxes/:id/primary", MailboxController, :set_primary
  end

  # Admin routes - require admin privileges
  scope "/admin", ElektrineWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    get "/", AdminController, :dashboard
    get "/users", AdminController, :users
    get "/users/:id/edit", AdminController, :edit
    put "/users/:id", AdminController, :update
    post "/users/:id/toggle_admin", AdminController, :toggle_admin
    get "/users/:id/ban", AdminController, :ban
    post "/users/:id/ban", AdminController, :confirm_ban
    post "/users/:id/unban", AdminController, :unban
    delete "/users/:id", AdminController, :delete
    get "/mailboxes", AdminController, :mailboxes
    get "/messages", AdminController, :messages
    get "/deletion-requests", AdminController, :deletion_requests
    get "/deletion-requests/:id", AdminController, :show_deletion_request
    post "/deletion-requests/:id/approve", AdminController, :approve_deletion_request
    post "/deletion-requests/:id/deny", AdminController, :deny_deletion_request
  end

  # Routes for all users (authenticated or not)
  scope "/", ElektrineWeb do
    pipe_through [:browser]

    delete "/logout", UserSessionController, :delete
  end

  # Other scopes may use custom stacks.
  scope "/api", ElektrineWeb do
    pipe_through :api

    # Ejabberd authentication routes
    post "/ejabberd/auth", EjabberdAuthController, :auth
    post "/ejabberd/isuser", EjabberdAuthController, :isuser
    post "/ejabberd/setpass", EjabberdAuthController, :setpass
    post "/ejabberd/get_avatar", EjabberdAuthController, :get_avatar
    post "/ejabberd/get_user_info", EjabberdAuthController, :get_user_info

    # Email API endpoints
    post "/postal/inbound", PostalInboundController, :create

    # Flutter app API endpoints
    scope "/temp-mail", as: :api do
      # Create a new temporary mailbox
      post "/", API.TemporaryMailboxController, :create

      # Get mailbox details and messages by token
      get "/:token", API.TemporaryMailboxController, :show

      # Extend mailbox expiration
      post "/:token/extend", API.TemporaryMailboxController, :extend

      # Get a specific message from a mailbox
      get "/:token/message/:id", API.TemporaryMailboxController, :get_message

      # Delete a message
      delete "/:token/message/:id", API.TemporaryMailboxController, :delete_message
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview
  import Phoenix.LiveDashboard.Router

  # LiveDashboard for admins in production
  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    live_dashboard "/dashboard", metrics: ElektrineWeb.Telemetry
  end

  # Development-only routes
  if Application.compile_env(:elektrine, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
