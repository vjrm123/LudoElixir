# lib/ludo/application.ex
defmodule Ludo.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LudoWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:ludo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ludo.PubSub},
      # Registry: clave única = código de sala (string), valor = pid del GameServer
      {Registry, keys: :unique, name: Ludo.SalaRegistry},
      # DynamicSupervisor: arranca/para GameServers en caliente
      {DynamicSupervisor, name: Ludo.SalaSupervisor, strategy: :one_for_one},
      LudoWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Ludo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LudoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
