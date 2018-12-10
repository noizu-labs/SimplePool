#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Behaviour do
  @callback option_settings() :: Map.t

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.Pool.DefaultImplementation)
    option_settings = implementation.prepare_options(Macro.expand(options, __CALLER__))

    options = option_settings.effective_options
    #required = options.required
    default_modules = options.default_modules
    max_supervisors = options.max_supervisors
    quote do
      @behaviour Noizu.SimplePool.V2.Behaviour
      @implementation unquote implementation

      @parent unquote(__MODULE__)
      @module __MODULE__

      @module_str "#{@module}"

      @worker_state_entity @implementation.worker_state_entity(@module, unquote(options.worker_state_entity))

      @max_supervisors unquote(max_supervisors)
      @options unquote(Macro.escape(options))
      @option_settings unquote(Macro.escape(option_settings))


      # Related Modules.
      @pool @implementation.pool(@module)
      @pool_worker_supervisor @implementation.pool_worker_supervisor(@module)
      @pool_server @implementation.pool_server(@module)
      @pool_worker @implementation.pool_worker(@module)
      @pool_supervisor @implementation.pool_supervisor(@module) # @module

      #-------------------
      #
      #-------------------
      def pool(), do: @pool

      #-------------------
      #
      #-------------------
      def pool_worker_supervisor(), do: @pool_worker_supervisor

      #-------------------
      #
      #-------------------
      def pool_server(), do: @pool_server

      #-------------------
      #
      #-------------------
      def pool_supervisor(), do: @pool_supervisor

      #-------------------
      #
      #-------------------
      def pool_worker(), do: @pool_worker


      #-------------------
      # banner
      #-------------------
      def banner(msg), do: banner(@module_str, msg)
      defdelegate banner(header, msg), to: @implementation

      #-------------------
      #
      #-------------------
      def meta(), do: _imp_meta(@module)
      defdelegate _imp_meta(module), to: @implementation, as: :meta

      #-------------------
      #
      #-------------------
      def meta(update), do: _imp_meta(@module, update)
      defdelegate _imp_meta(module, update), to: @implementation, as: :meta

      #-------------------
      #
      #-------------------
      def meta_init(), do: _imp_meta_init(@module)
      defdelegate _imp_meta_init(module), to: @implementation, as: :meta_init

      #-------------------
      #
      #-------------------
      def options(), do: @options

      #-------------------
      #
      #-------------------
      def option_settings(), do: @option_settings



      defoverridable [
        banner: 1,
        banner: 2,
        option_settings: 0,
        options: 0,
      ]

      if (unquote(default_modules.worker)) do
        defmodule Worker do
          use Noizu.SimplePool.WorkerBehaviour, unquote(options.worker_options)
        end
      end

      if (unquote(default_modules.server)) do
        defmodule Server do
          use Noizu.SimplePool.ServerBehaviour, unquote(options.server_options)
          def lazy_load(state), do: state
        end
      end

      if (unquote(default_modules.worker_supervisor)) do
        module = __MODULE__
        for i <- 1 .. @max_supervisors do
          defmodule :"#{module}.WorkerSupervisor_S#{i}" do
            use Noizu.SimplePool.V2.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
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
