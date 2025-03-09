defmodule ElektrineWeb.AboutController do
  use ElektrineWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end 