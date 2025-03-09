defmodule ElektrineWeb.Router do
  use ElektrineWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ElektrineWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug ElektrineWeb.Plugs.Auth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug ElektrineWeb.Plugs.Auth, :authenticate_user
  end

  scope "/", ElektrineWeb do
    pipe_through :browser

    get "/", PageController, :home
    
    # About page
    get "/about", AboutController, :index
    
    # Legal pages
    get "/privacy", LegalController, :privacy
    get "/terms", LegalController, :terms
    
    # Authentication routes
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
    
    # Registration routes
    get "/register", RegistrationController, :new
    post "/register", RegistrationController, :create
    
    # Password reset routes
    get "/forgot-password", ForgotPasswordController, :new
    post "/forgot-password", ForgotPasswordController, :create
    get "/reset-password/:token", ResetPasswordController, :edit
    put "/reset-password/:token", ResetPasswordController, :update
  end

  # Routes that require authentication
  scope "/", ElektrineWeb do
    pipe_through [:browser, :authenticated]
    
    # Protected routes go here
  end

  # Other scopes may use custom stacks.
  # scope "/api", ElektrineWeb do
  #   pipe_through :api
  # end

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
