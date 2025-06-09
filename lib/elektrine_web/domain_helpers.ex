defmodule ElektrineWeb.DomainHelpers do
  @moduledoc """
  Helper functions for working with multiple domains.
  """

  @doc """
  Returns the current domain from the connection or socket.
  Falls back to the configured email domain if not available.
  """
  def current_domain(%Plug.Conn{} = conn) do
    case get_host_from_conn(conn) do
      nil -> default_email_domain()
      host -> extract_domain(host)
    end
  end

  def current_domain(%Phoenix.LiveView.Socket{} = socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: _address} ->
        # In LiveView, we can get the host from the URI
        case socket.assigns[:__changed__] do
          %{} -> default_email_domain()
          _ -> default_email_domain()
        end
      _ -> default_email_domain()
    end
  end

  def current_domain(_), do: default_email_domain()

  @doc """
  Returns all supported domains for this application.
  """
  def supported_domains do
    Application.get_env(:elektrine, :email)[:supported_domains] || ["elektrine.com"]
  end

  @doc """
  Returns the default email domain.
  """
  def default_email_domain do
    Application.get_env(:elektrine, :email)[:domain] || "elektrine.com"
  end

  @doc """
  Checks if a domain is supported by this application.
  """
  def supported_domain?(domain) do
    domain in supported_domains()
  end

  @doc """
  Generates an email address using the appropriate domain for the current context.
  """
  def generate_email(username, conn_or_socket \\ nil) do
    domain = if conn_or_socket do
      current_domain(conn_or_socket)
    else
      default_email_domain()
    end
    
    "#{username}@#{domain}"
  end

  # Private helper functions

  defp get_host_from_conn(conn) do
    case Plug.Conn.get_req_header(conn, "host") do
      [host | _] -> host
      _ -> nil
    end
  end

  defp extract_domain(host) do
    # Remove port if present
    host
    |> String.split(":")
    |> List.first()
    |> remove_www_prefix()
  end

  defp remove_www_prefix("www." <> domain), do: domain
  defp remove_www_prefix(domain), do: domain
end