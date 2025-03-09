defmodule Elektrine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ElektrineWeb.Telemetry,
      Elektrine.Repo,
      {DNSCluster, query: Application.get_env(:elektrine, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Elektrine.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Elektrine.Finch},
      # Start a worker by calling: Elektrine.Worker.start_link(arg)
      # {Elektrine.Worker, arg},
      # Start to serve requests, typically the last entry
      ElektrineWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Elektrine.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ElektrineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
