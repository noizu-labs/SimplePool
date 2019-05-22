#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule Noizu.SimplePool.V2.MonitoringFramework.ClusterMonitor do
  @behaviour Noizu.SimplePool.V2.MonitoringFramework.ClusterMonitorBehaviour
  alias Noizu.ElixirCore.CallingContext
  alias Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration
  use Noizu.SimplePool.V2.StandAloneServiceBehaviour,
      default_modules: [:pool_supervisor, :monitor],
      worker_state_entity: nil,
      verbose: false



  defdelegate rebalance(source_servers, target_servers, services, context, opts), to: __MODULE__.Server
  defdelegate offload(servers, services, context, opts), to: __MODULE__.Server
  defdelegate lock_services(servers, services, context, opts), to: __MODULE__.Server
  defdelegate release_services(servers, services, context, opts), to: __MODULE__.Server
  defdelegate select_host(ref, service, context, opts), to: __MODULE__.Server
  defdelegate record_cluster_event!(event, details, context, opts), to: __MODULE__.Server
  defdelegate health_check(context, opts), to: __MODULE__.Server

  defmodule Server do
    @vsn 1.0
    alias Noizu.SimplePool.V2.Server.State

    use Noizu.SimplePool.V2.ServerBehaviour,
        worker_state_entity: nil,
        server_monitor: Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor
    require Logger

    def initial_state(args, context) do
      # @todo attempt to load configuration from persistence store
      %State{
        pool: pool(),
        entity: nil,
        status_details: :pending,
        extended: %{},
        environment_details: {:error, :nyi},
        options: option_settings()
      }
    end

    def rebalance(source_servers, target_servers, services, context, opts), do: :wip
    def offload(servers, services, context, opts), do: :wip
    def lock_services(servers, services, context, opts), do: :wip
    def release_services(servers, services, context, opts), do: :wip
    def select_host(ref, service, context, opts), do: :wip

    def health_check(context, opts), do: :wip


    def record_cluster_event!(event, details, context, opts) do
      Logger.info("TODO - write to ClusterEventTable #{inspect event}")
    end

  end # end defmodule Server
end