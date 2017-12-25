#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Support.TestTwoPool do
  #alias Noizu.Scaffolding.CallingContext
  use Noizu.SimplePool.Behaviour,
      default_modules: [:pool_supervisor, :worker_supervisor],
      worker_state_entity: Noizu.SimplePool.Support.TestTwoWorkerEntity,
      verbose: false

  defmodule Worker do
    @vsn 1.0
    use Noizu.SimplePool.WorkerBehaviour,
        worker_state_entity: Noizu.SimplePool.Support.TestTwoWorkerEntity,
        verbose: false
    require Logger
  end # end worker

  #=============================================================================
  # @Server
  #=============================================================================
  defmodule Server do
    @vsn 1.0
    use Noizu.SimplePool.ServerBehaviour,
        worker_state_entity: Noizu.SimplePool.Support.TestTwoWorkerEntity
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
