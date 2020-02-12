#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Support.TestV2ThreePool do
  #alias Noizu.Scaffolding.CallingContext
  use Noizu.SimplePool.V2.PoolBehaviour,
      default_modules: [:pool_supervisor, :worker_supervisor, :monitor],
      worker_state_entity: Noizu.SimplePool.Support.TestV2ThreeWorkerEntity,
      dispatch_table: Noizu.SimplePool.TestDatabase.TestV2ThreePool.DispatchTable,
      verbose: false

  defmodule Worker do
    @vsn 1.0
    use Noizu.SimplePool.V2.WorkerBehaviour,
        worker_state_entity: Noizu.SimplePool.Support.TestV2ThreeWorkerEntity,
        verbose: false
    require Logger
  end # end worker

  #=============================================================================
  # @Server
  #=============================================================================
  defmodule Server do
    @vsn 1.0
    use Noizu.SimplePool.V2.ServerBehaviour,
        worker_state_entity: Noizu.SimplePool.Support.TestV2ThreeWorkerEntity,
        worker_lookup_handler: Noizu.SimplePool.WorkerLookupBehaviour.Dynamic
  end # end defmodule
  #---------------------------------------------------------------------------
  # Convenience Methods
  #---------------------------------------------------------------------------
  def test_s_call!(identifier, value, context) do
    __MODULE__.Server.Router.s_call!(identifier, {:test_s_call!, value}, context)
  end

  def test_s_call(identifier, value, context) do
    __MODULE__.Server.Router.s_call(identifier, {:test_s_call, value}, context)
  end

  def test_s_cast!(identifier, value, context) do
    __MODULE__.Server.Router.s_cast!(identifier, {:test_s_cast!, value}, context)
  end

  def test_s_cast(identifier, value, context) do
    __MODULE__.Server.Router.s_cast(identifier, {:test_s_cast, value}, context)
  end

end # end defmodule
