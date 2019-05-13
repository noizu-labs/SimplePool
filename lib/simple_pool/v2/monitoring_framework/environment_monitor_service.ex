#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule Noizu.SimplePool.V2.MonitoringFramework.EnvironmentMonitorService do
  @behaviour Noizu.SimplePool.V2.MonitoringFramework.MonitorBehaviour

  use Noizu.SimplePool.V2.StandAloneServiceBehaviour,
      default_modules: [:pool_supervisor, :monitor],
      worker_state_entity: nil,
      verbose: false

  defmodule Server do
    @vsn 1.0
    use Noizu.SimplePool.V2.ServerBehaviour,
        worker_state_entity: nil,
        server_monitor: __MODULE__,
        worker_lookup_handler: Noizu.SimplePool.WorkerLookupBehaviour.Dynamic
    #alias Noizu.SimplePool.Support.TestTwoWorkerEntity


  end # end defmodule Server

end