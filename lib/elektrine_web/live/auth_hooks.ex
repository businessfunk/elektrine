defmodule ElektrineWeb.Live.AuthHooks do
  @moduledoc """
  Provides LiveView authentication hooks.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias Elektrine.Accounts
  alias Phoenix.LiveView.Socket

  @max_age 60 * 60 * 24 * 60

  @doc """
  Used for LiveView pages that require authentication.
  """
  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket =
      socket
      |> assign_current_user(session)

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