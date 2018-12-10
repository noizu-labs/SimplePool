#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.PoolSupervisorBehaviour do
  @callback option_settings() :: Map.t
  @callback start_link(any, any) :: any
  @callback start_children(any, any, any) :: any

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.PoolSupervisor.DefaultImplementation)
    option_settings = implementation.prepare_options(options)
    options = option_settings.effective_options

    #required = options.required
    max_restarts = options.max_restarts
    max_seconds = options.max_seconds
    strategy = options.strategy
    #verbose = options.verbose
    features = MapSet.new(options.features)


    quote do
      @behaviour Noizu.SimplePool.V2.PoolSupervisorBehaviour
      use Supervisor

      @implementation unquote(implementation)
      @parent unquote(__MODULE__)
      @module __MODULE__
      @module_name "#{@module}"

      @auto_load unquote(MapSet.member?(features, :auto_load))

      # Related Modules.
      @pool @implementation.pool(@module)
      @meta_key :"meta_#{@module}"

      @options unquote(Macro.escape(options))
      @option_settings unquote(Macro.escape(option_settings))

      @strategy unquote(strategy)
      @max_seconds unquote(max_seconds)
      @max_restarts unquote(max_restarts)

      #-------------------
      #
      #-------------------
      def banner(msg), do: banner(@module_name, msg)
      defdelegate banner(header, msg), to: @pool

      #-------------------
      #
      #-------------------
      def _strategy(), do: @strategy
      def _max_seconds(), do: @max_seconds

      #-------------------
      #
      #-------------------
      def _max_restarts(), do: @max_restarts

      #-------------------
      #
      #-------------------
      def auto_load(), do: @auto_load

      #-------------------
      #
      #-------------------
      def verbose(), do: meta()[:verbose]

      #-------------------
      #
      #-------------------
      def meta_key(), do: @meta_key

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
      def option_settings(), do: @option_settings

      #-------------------
      #
      #-------------------
      def options(), do: @options

      #-------------------
      #
      #-------------------
      defdelegate pool(), to: @pool

      #-------------------
      #
      #-------------------
      defdelegate pool_worker_supervisor(), to: @pool

      #-------------------
      #
      #-------------------
      defdelegate pool_server(), to: @pool

      #-------------------
      #
      #-------------------
      defdelegate pool_supervisor(), to: @pool

      #-------------------
      #
      #-------------------
      defdelegate pool_worker(), to: @pool

      #-------------------
      #
      #-------------------
      def start_link(context, definition \\ :auto), do: _imp_start_link(@module, context, definition)
      defdelegate _imp_start_link(module, context, definition), to: @implementation, as: :start_link

      #-------------------
      #
      #-------------------
      def start_children(sup, context, definition \\ :auto), do: _imp_start_children(@module, sup, context, definition)
      defdelegate _imp_start_children(module, sup, context, definition), to: @implementation, as: :start_children

      #-------------------
      #
      #-------------------
      def start_worker_supervisors(sup, context, definition), do: _imp_start_worker_supervisors(@module, sup, context, definition)
      defdelegate _imp_start_worker_supervisors(module, sup, context, definition), to: @implementation, as: :start_worker_supervisors

      #-------------------
      #
      #-------------------
      def init(arg), do: _imp_init(@module, arg)
      defdelegate _imp_init(module, arg), to: @implementation, as: :init

      #-------------------
      #
      #-------------------
      def handle_call(msg, from, s), do: handle_call_catchall(msg, from, s)
      def handle_cast(msg, s), do: handle_cast_catchall(msg, s)
      def handle_info(msg, s), do: handle_info_catchall(msg, s)

      def handle_call_catchall(msg, from, s), do: _imp_handle_call_catchall(@module, msg, from, s)
      defdelegate _imp_handle_call_catchall(module, msg, from, s), to: @implementation, as: :handle_call_catchall

      def handle_cast_catchall(msg, s), do: _imp_handle_cast_catchall(@module, msg, s)
      defdelegate _imp_handle_cast_catchall(module, msg, s), to: @implementation, as: :handle_cast_catchall

      def handle_info_catchall(msg, s), do: _imp_handle_info_catchall(@module, msg, s)
      defdelegate _imp_handle_info_catchall(module, msg, s), to: @implementation, as: :handle_info_catchall
    end # end quote
  end #end __using__

end