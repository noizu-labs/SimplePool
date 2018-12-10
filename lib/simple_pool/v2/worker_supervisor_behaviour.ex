#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerSupervisorBehaviour do
  require Logger
  @callback start_link(any, any) :: any

  @callback child(any, any) :: any
  @callback child(any, any, any) :: any
  @callback child(any, any, any, any) :: any

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.WorkerSupervisor.DefaultImplementation)
    option_settings = implementation.prepare_options(options)
    options = option_settings.effective_options

    max_restarts = options.max_restarts
    max_seconds = options.max_seconds
    strategy = options.strategy
    restart_type = options.restart_type

    quote do

      @behaviour Noizu.SimplePool.V2.WorkerSupervisorBehaviour
      use Supervisor

      @implementation unquote(implementation)
      @parent unquote(__MODULE__)
      @module __MODULE__
      @module_name "#{@module}"

      # Related Modules.
      @pool @implementation.pool(@module)
      @meta_key :"meta_#{@module}"

      @options unquote(Macro.escape(options))
      @option_settings unquote(Macro.escape(option_settings))

      @strategy unquote(strategy)
      @restart_type unquote(restart_type)
      @max_seconds unquote(max_seconds)
      @max_restarts unquote(max_restarts)

      #-------------------
      #
      #-------------------
      def _strategy(), do: @strategy
      def _max_seconds(), do: @max_seconds
      def _max_restarts(), do: @max_restarts
      def _restart_type(), do: @restart_type

      #-------------------
      #
      #-------------------
      def banner(msg), do: banner(@module_name, msg)
      defdelegate banner(header, msg), to: @pool

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
      def start_link(definition, context), do: _imp_start_link(@module, context, definition) # TODO switch incoming order.
      defdelegate _imp_start_link(module, context, definition), to: @implementation, as: :start_link

      #-------------------
      #
      #-------------------
      def child(ref, context), do: _imp_child(@module, ref, context)
      defdelegate _imp_child(module, ref, context), to: @implementation, as: :child

      def child(ref, params, context), do: _imp_child(@module, ref, params, context)
      defdelegate _imp_child(module, ref, params, context), to: @implementation, as: :child

      def child(ref, params, context, options), do: _imp_child(@module, ref, params, context, options)
      defdelegate _imp_child(module, ref, params, context, options), to: @implementation, as: :child

      #-------------------
      #
      #-------------------
      def init(args), do: _imp_init(@module, args)
      defdelegate _imp_init(module, args), to: @implementation, as: :init

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
