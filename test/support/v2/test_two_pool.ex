#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Support.TestV2TwoPool do
  #alias Noizu.Scaffolding.CallingContext
  use Noizu.SimplePool.V2.Behaviour,
      default_modules: [:pool_supervisor, :worker_supervisor],
      worker_state_entity: Noizu.SimplePool.Support.TestV2TwoWorkerEntity,
      verbose: false

  defmodule Worker do
    @vsn 1.0
    use Noizu.SimplePool.WorkerBehaviour,
        worker_state_entity: Noizu.SimplePool.Support.TestV2TwoWorkerEntity,
        verbose: false
    require Logger
  end # end worker

  #=============================================================================
  # @Server
  #=============================================================================
  defmodule Server do
    @vsn 1.0
    use Noizu.SimplePool.ServerBehaviour,
        worker_state_entity: Noizu.SimplePool.Support.TestV2TwoWorkerEntity,
        server_monitor: Noizu.MonitoringFramework.EnvironmentPool.Server,
        worker_lookup_handler: Noizu.SimplePool.WorkerLookupBehaviour.Dynamic
    #alias Noizu.SimplePool.Support.TestTwoWorkerEntity

    #---------------------------------------------------------------------------
    # Convenience Methods
    #---------------------------------------------------------------------------
    def test_s_call!(identifier, value, context) do
      s_call!(identifier, {:test_s_call!, value}, context)
    end

    def test_s_call(identifier, value, context) do
      s_call(identifier, {:test_s_call, value}, context)
    end

    def test_s_cast!(identifier, value, context) do
      s_cast!(identifier, {:test_s_cast!, value}, context)
    end

    def test_s_cast(identifier, value, context) do
      s_cast(identifier, {:test_s_cast, value}, context)
    end




  end # end defmodule GoldenRatio.Components.Gateway.Server


end # end defmodule GoldenRatio.Components.Gateway
