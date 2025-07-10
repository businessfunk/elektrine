defmodule ElektrineWeb.PageController do
  use ElektrineWeb, :controller

  def home(conn, _params) do
    # Always skip layout for homepage to maintain fullscreen design
    render(conn, :home, layout: false)
  end
end
