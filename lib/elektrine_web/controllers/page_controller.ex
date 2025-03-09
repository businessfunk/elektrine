defmodule ElektrineWeb.PageController do
  use ElektrineWeb, :controller

  def home(conn, _params) do
    # Use the app layout to include our new navbar
    render(conn, :home)
  end
end
