defmodule CineDie.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CineDieWeb.Telemetry,
      CineDie.Repo,
      {Oban, Application.fetch_env!(:cine_die, Oban)},
      {DNSCluster, query: Application.get_env(:cine_die, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CineDie.PubSub},
      # Start a worker by calling: CineDie.Worker.start_link(arg)
      # {CineDie.Worker, arg},
      # Start to serve requests, typically the last entry
      CineDieWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CineDie.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CineDieWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
