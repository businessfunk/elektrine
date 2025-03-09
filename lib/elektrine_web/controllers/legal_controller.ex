defmodule ElektrineWeb.LegalController do
  use ElektrineWeb, :controller

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def terms(conn, _params) do
    render(conn, :terms)
  end
end 