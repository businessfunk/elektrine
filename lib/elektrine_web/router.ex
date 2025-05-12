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
