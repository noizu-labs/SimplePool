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

  end # end defmodule Server
end