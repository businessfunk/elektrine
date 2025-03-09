defmodule ElektrineWeb.Components.Footer do
  use Phoenix.Component
  
  use Phoenix.VerifiedRoutes,
    endpoint: ElektrineWeb.Endpoint,
    router: ElektrineWeb.Router,
    statics: ElektrineWeb.static_paths()

  @doc """
  Renders a simplified footer.

  ## Examples

      <.footer />
  """
  def footer(assigns) do
    ~H"""
    <footer class="bg-theme-dark border-t border-theme-primary-transparent-light mt-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="py-6">
          <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
            <div>
              <div class="flex items-center mb-4">
                <div class="w-6 h-6 flex items-center justify-center mr-2">
                  <div class="text-theme-light text-xl font-bold transform -rotate-45 inline-block">E</div>
                </div>
                <span class="text-theme-light text-lg font-semibold">Elektrine</span>
              </div>
              <p class="text-theme-light-dim text-sm">
                Modern email for the digital age.
              </p>
            </div>
            
            <div>
              <h3 class="text-theme-primary font-medium mb-3 text-sm uppercase tracking-wider">Links</h3>
              <ul class="space-y-2">
                <li><a href="/" class="text-theme-light-dim hover:text-theme-primary text-sm transition-colors duration-150">Home</a></li>
                <li><a href="/about" class="text-theme-light-dim hover:text-theme-primary text-sm transition-colors duration-150">About</a></li>
                <li><a href="/login" class="text-theme-light-dim hover:text-theme-primary text-sm transition-colors duration-150">Login</a></li>
                <li><a href="/register" class="text-theme-light-dim hover:text-theme-primary text-sm transition-colors duration-150">Register</a></li>
              </ul>
            </div>
            
            <div>
              <h3 class="text-theme-primary font-medium mb-3 text-sm uppercase tracking-wider">Legal</h3>
              <ul class="space-y-2">
                <li><a href="/privacy" class="text-theme-light-dim hover:text-theme-primary text-sm transition-colors duration-150">Privacy Policy</a></li>
                <li><a href="/terms" class="text-theme-light-dim hover:text-theme-primary text-sm transition-colors duration-150">Terms of Service</a></li>
              </ul>
            </div>
          </div>
          
          <div class="border-t border-theme-primary-transparent-light mt-8 pt-6 flex flex-col md:flex-row justify-between items-center">
            <p class="text-theme-light-dim text-sm">© <%= DateTime.utc_now().year %> Elektrine. All rights reserved.</p>
          </div>
        </div>
      </div>
    </footer>
    """
  end
end 