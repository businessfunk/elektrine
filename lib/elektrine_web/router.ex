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
  end

  # Routes that are specifically for unauthenticated users
  scope "/", ElektrineWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/register", UserRegistrationController, :new
    post "/register", UserRegistrationController, :create
    get "/login", UserSessionController, :new
    post "/login", UserSessionController, :create
  end

  # Routes that require authentication
  scope "/", ElektrineWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/account", UserSettingsController, :edit
    put "/account", UserSettingsController, :update
    get "/account/password", UserSettingsController, :edit_password
    put "/account/password", UserSettingsController, :update_password

    # Email LiveView routes - each is a separate LiveView with individual templates
    live_session :authenticated, on_mount: {ElektrineWeb.Live.AuthHooks, :require_authenticated_user} do
      live "/email", EmailLive.Index, :index
      live "/email/inbox", EmailLive.Inbox, :inbox
      live "/email/sent", EmailLive.Sent, :sent
      live "/email/spam", EmailLive.Spam, :spam
      live "/email/archive", EmailLive.Archive, :archive
      live "/email/compose", EmailLive.Compose, :new
      live "/email/view/:id", EmailLive.Show, :show
      live "/email/contacts", EmailLive.Contacts, :contacts
      live "/email/temp", EmailLive.TempMail, :index
      live "/email/temp/:token", EmailLive.TempMail, :show
      live "/email/temp/:token/message/:id", EmailLive.TempMail, :message
    end

    # Mailbox management (removed for single mailbox per user)
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

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:elektrine, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ElektrineWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
