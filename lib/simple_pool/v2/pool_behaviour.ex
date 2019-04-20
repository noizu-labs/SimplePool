#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.PoolBehaviour do
  @moduledoc """
    The Noizu.SimplePool.V2.Behaviour provides the entry point for Worker Pools.
    The developer will define a pool such as ChatRoomPool that uses the Noizu.SimplePool.V2.Behaviour Implementation
    before going on to define worker and server implementations.

    The module is relatively straight forward, it provides methods to get pool information (pool worker, pool supervisor)
    compile options, runtime settings (via the FastGlobal library and our meta function).
  """

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.Pool.DefaultImplementation)
    option_settings = implementation.prepare_options(Macro.expand(options, __CALLER__))
    options = option_settings.effective_options
    default_modules = options.default_modules
    max_supervisors = options.max_supervisors

    quote do
      require Logger
      @behaviour Noizu.SimplePool.V2.PoolBehaviour
      @implementation unquote(implementation)
      @module __MODULE__
      @max_supervisors unquote(max_supervisors)

      use Noizu.SimplePool.V2.PoolSettingsBehaviour.Base, unquote([option_settings: option_settings])

      @doc """
      Initialize meta data for this pool. (override default provided by PoolSettingsBehaviour)
      """
      def meta_init(), do: @implementation.meta_init(@module)

      defoverridable []

      if (unquote(default_modules.worker)) do
        defmodule Worker do
          use Noizu.SimplePool.V2.WorkerBehaviour, unquote(options.worker_options)
        end
      end

      if (unquote(default_modules.server)) do
        defmodule Server do
          use Noizu.SimplePool.V2.ServerBehaviour, unquote(options.server_options)
          def lazy_load(state), do: state
        end
      end

      if (unquote(default_modules.worker_supervisor)) do
        #module = __MODULE__
        #for i <- 1 .. @max_supervisors do
         # defmodule :"#{module}.WorkerSupervisor_S#{i}" do
            #use Noizu.SimplePool.V2.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
         #end
        #end
        defmodule WorkerSupervisor do
          use Noizu.SimplePool.V2.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
      end

      if (unquote(default_modules.pool_supervisor)) do
        defmodule PoolSupervisor do
          use Noizu.SimplePool.V2.PoolSupervisorBehaviour, unquote(options.pool_supervisor_options)
        end
      end
    end # end quote
  end #end __using__
end
