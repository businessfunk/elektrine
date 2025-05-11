defmodule ElektrineWeb.PageController do
  use ElektrineWeb, :controller

  def home(conn, _params) do
    # Use the app layout when user is logged in, otherwise use no layout
    if conn.assigns[:current_user] do
      render(conn, :home)
    else
      # Skip layout for anonymous users to show the landing page
      render(conn, :home, layout: false)
    end
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def contact(conn, _params) do
    render(conn, :contact)
  end
end
