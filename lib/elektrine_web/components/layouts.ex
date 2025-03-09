defmodule ElektrineWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use ElektrineWeb, :controller` and
  `use ElektrineWeb, :live_view`.
  """
  use ElektrineWeb, :html
  
  # Import Phoenix.Controller for current_path/1 and get_csrf_token/0
  import Phoenix.Controller, only: [current_path: 1, get_csrf_token: 0]
  
  # Import components so they're available in all layouts
  import ElektrineWeb.Components.Navbar
  import ElektrineWeb.Components.Footer

  embed_templates "layouts/*"
end
