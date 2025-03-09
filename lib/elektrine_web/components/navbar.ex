defmodule ElektrineWeb.Components.Navbar do
  use Phoenix.Component
  
  # Import Phoenix.Component for link/1
  alias Phoenix.Component
  
  # Import the verified_routes function to use the ~p sigil
  import Phoenix.VerifiedRoutes, only: [sigil_p: 2]
  use Phoenix.VerifiedRoutes,
    endpoint: ElektrineWeb.Endpoint,
    router: ElektrineWeb.Router,
    statics: ElektrineWeb.static_paths()
    
  # Import JS commands
  alias Phoenix.LiveView.JS

  @doc """
  Renders a modern, Silicon Valley-style navbar.

  ## Examples

      <.navbar current_user={@current_user} current_path={@current_path} />
  """
  attr :current_user, :map, default: nil
  attr :current_path, :string, default: "/"

  def navbar(assigns) do
    ~H"""
    <nav class="bg-theme-dark border-b border-theme-primary-transparent-light sticky top-0 z-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16">
          <!-- Logo and primary navigation -->
          <div class="flex">
            <div class="flex-shrink-0 flex items-center">
              <a href="/" class="flex items-center hover:no-underline">
                <div class="w-8 h-8 flex items-center justify-center mr-2">
                  <div class="text-theme-light text-2xl font-bold transform -rotate-45 inline-block">E</div>
                </div>
                <span class="text-theme-light text-xl font-semibold">Elektrine</span>
              </a>
            </div>
            <div class="hidden sm:ml-6 sm:flex sm:space-x-8">
              <.nav_link path="/" current_path={@current_path}>Home</.nav_link>
              <.nav_link path="/about" current_path={@current_path}>About</.nav_link>
            </div>
          </div>

          <!-- User navigation -->
          <div class="hidden sm:ml-6 sm:flex sm:items-center">
            <!-- User dropdown -->
            <%= if @current_user do %>
              <div class="ml-3 relative group">
                <div>
                  <button type="button" class="bg-theme-dark flex text-sm rounded-full focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-theme-primary" id="user-menu-button" aria-expanded="false" aria-haspopup="true">
                    <span class="sr-only">Open user menu</span>
                    <div class="h-8 w-8 rounded-full bg-theme-primary-transparent-light flex items-center justify-center text-theme-light">
                      <%= String.first(@current_user.username) %>
                    </div>
                  </button>
                </div>
                <div class="origin-top-right absolute right-0 mt-2 w-48 rounded-md shadow-lg py-1 bg-theme-dark border border-theme-primary-transparent-light ring-1 ring-black ring-opacity-5 focus:outline-none transform opacity-0 scale-95 group-hover:opacity-100 group-hover:scale-100 transition ease-in-out duration-100" role="menu" aria-orientation="vertical" aria-labelledby="user-menu-button" tabindex="-1">
                  <a href="#" class="block px-4 py-2 text-sm text-theme-light hover:text-theme-primary hover:bg-theme-primary-transparent-light" role="menuitem" tabindex="-1" id="user-menu-item-0">Your Profile</a>
                  <a href="#" class="block px-4 py-2 text-sm text-theme-light hover:text-theme-primary hover:bg-theme-primary-transparent-light" role="menuitem" tabindex="-1" id="user-menu-item-1">Settings</a>
                  <Component.link href={~p"/logout"} method="delete" class="block px-4 py-2 text-sm text-theme-light hover:text-theme-primary hover:bg-theme-primary-transparent-light" role="menuitem" tabindex="-1" id="user-menu-item-2">
                    Sign out
                  </Component.link>
                </div>
              </div>
            <% else %>
              <div class="flex items-center space-x-4">
                <.nav_link path="/login" current_path={@current_path} class="px-3 py-2 rounded-md text-sm font-medium transition-colors duration-150">Sign in</.nav_link>
                <.nav_link path="/register" current_path={@current_path} class="px-3 py-2 rounded-md text-sm font-medium transition-colors duration-150">Sign up</.nav_link>
              </div>
            <% end %>
          </div>

          <!-- Mobile menu button -->
          <div class="flex items-center sm:hidden">
            <button 
              type="button" 
              class="inline-flex items-center justify-center p-2 rounded-md text-theme-light hover:text-theme-primary hover:bg-theme-primary-transparent-light focus:outline-none focus:ring-2 focus:ring-inset focus:ring-theme-primary" 
              aria-controls="mobile-menu" 
              aria-expanded="false"
              phx-click={JS.toggle(to: "#mobile-menu") |> JS.toggle(to: "#menu-open-icon") |> JS.toggle(to: "#menu-close-icon")}
            >
              <span class="sr-only">Open main menu</span>
              <!-- Icon when menu is closed -->
              <svg id="menu-open-icon" class="block h-6 w-6" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
              </svg>
              <!-- Icon when menu is open -->
              <svg id="menu-close-icon" class="hidden h-6 w-6" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
      </div>

      <!-- Mobile menu, show/hide based on menu state -->
      <div class="hidden sm:hidden" id="mobile-menu">
        <div class="pt-2 pb-3 space-y-1">
          <.mobile_nav_link path="/" current_path={@current_path}>Home</.mobile_nav_link>
          <.mobile_nav_link path="/about" current_path={@current_path}>About</.mobile_nav_link>
        </div>
        
        <!-- Mobile user menu -->
        <%= if @current_user do %>
          <div class="pt-4 pb-3 border-t border-theme-primary-transparent-light">
            <div class="flex items-center px-4">
              <div class="flex-shrink-0">
                <div class="h-10 w-10 rounded-full bg-theme-primary-transparent-light flex items-center justify-center text-theme-light">
                  <%= String.first(@current_user.username) %>
                </div>
              </div>
              <div class="ml-3">
                <div class="text-base font-medium text-theme-light"><%= @current_user.username %></div>
                <div class="text-sm font-medium text-theme-light-dim"><%= @current_user.recovery_email %></div>
              </div>
            </div>
            <div class="mt-3 space-y-1">
              <a href="#" class="block px-4 py-2 text-base font-medium text-theme-light hover:text-theme-primary hover:bg-theme-primary-transparent-light">
                Your Profile
              </a>
              <a href="#" class="block px-4 py-2 text-base font-medium text-theme-light hover:text-theme-primary hover:bg-theme-primary-transparent-light">
                Settings
              </a>
              <Component.link href={~p"/logout"} method="delete" class="block px-4 py-2 text-base font-medium text-theme-light hover:text-theme-primary hover:bg-theme-primary-transparent-light">
                Sign out
              </Component.link>
            </div>
          </div>
        <% else %>
          <div class="pt-4 pb-3 border-t border-theme-primary-transparent-light">
            <div class="flex items-center justify-center space-x-4 px-4">
              <.mobile_nav_link path="/login" current_path={@current_path} class="px-3 py-2 rounded-md text-base font-medium transition-colors duration-150">Sign in</.mobile_nav_link>
              <.mobile_nav_link path="/register" current_path={@current_path} class="px-3 py-2 rounded-md text-base font-medium transition-colors duration-150">Sign up</.mobile_nav_link>
            </div>
          </div>
        <% end %>
      </div>
    </nav>
    """
  end

  # Helper component for desktop navigation links
  attr :path, :string, required: true
  attr :current_path, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def nav_link(assigns) do
    active = assigns.current_path == assigns.path
    
    assigns = assign(assigns, :active, active)
    assigns = assign(assigns, :classes, nav_link_classes(active, assigns.class))
    
    ~H"""
    <a href={@path} class={@classes}>
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  # Helper component for mobile navigation links
  attr :path, :string, required: true
  attr :current_path, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def mobile_nav_link(assigns) do
    active = assigns.current_path == assigns.path
    
    assigns = assign(assigns, :active, active)
    assigns = assign(assigns, :classes, mobile_nav_link_classes(active, assigns.class))
    
    ~H"""
    <a href={@path} class={@classes}>
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  # Helper function to generate desktop nav link classes
  defp nav_link_classes(active, additional_classes) do
    base_classes = "inline-flex items-center px-1 pt-1 border-b-2 text-sm font-medium transition-colors duration-150 #{additional_classes}"
    
    if active do
      "#{base_classes} border-theme-primary text-theme-light"
    else
      "#{base_classes} border-transparent text-theme-light-dim hover:text-theme-primary hover:border-theme-primary-transparent"
    end
  end

  # Helper function to generate mobile nav link classes
  defp mobile_nav_link_classes(active, additional_classes) do
    base_classes = "block pl-3 pr-4 py-2 border-l-4 text-base font-medium #{additional_classes}"
    
    if active do
      "#{base_classes} bg-theme-primary-transparent-light text-theme-light border-theme-primary"
    else
      "#{base_classes} border-transparent text-theme-light-dim hover:text-theme-primary hover:bg-theme-primary-transparent-light hover:border-theme-primary-transparent"
    end
  end
end 