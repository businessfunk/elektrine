defmodule ElektrineWeb.Live.AuthHooks do
  @moduledoc """
  Provides LiveView authentication hooks.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias Elektrine.Accounts

  @max_age 60 * 60 * 24 * 60

  @doc """
  Used for LiveView pages that require authentication.
  """
  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket =
      socket
      |> assign_current_user(session)
      |> assign_current_uri()

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You must log in to access this page.")

      {:halt, redirect(socket, to: "/login")}
    end
  end

  defp assign_current_user(socket, session) do
    assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        user_from_token(user_token)
      end
    end)
  end

  defp assign_current_uri(socket) do
    current_path = case socket do
      %{view: view} -> 
        # Extract path from the LiveView module name and route
        case view do
          ElektrineWeb.EmailLive.Inbox -> "/email/inbox"
          ElektrineWeb.EmailLive.Sent -> "/email/sent"
          ElektrineWeb.EmailLive.Compose -> "/email/compose"
          ElektrineWeb.EmailLive.Show -> "/email/view"
          ElektrineWeb.EmailLive.Index -> "/email"
          _ -> "/email"
        end
      _ -> 
        "/email"
    end
    assign(socket, :current_path, current_path)
  end

  defp user_from_token(token) do
    case Phoenix.Token.verify(ElektrineWeb.Endpoint, "user auth", token, max_age: @max_age) do
      {:ok, user_id} ->
        try do
          Accounts.get_user!(user_id)
        rescue
          _ -> nil
        end
      {:error, _} -> nil
    end
  end
end