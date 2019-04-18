#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerSupervisorBehaviour do
  @moduledoc """
    WorkerSupervisorBehaviour provides the logic for managing a pool of workers. The top level Pool Supervisors will generally
    contain a number of WorkerSupervisors that in turn are referenced by Pool.Server to access, kill and spawn worker processes.

    @todo increase level of OTP nesting and hide some of the communication complexity from Pool.Server
  """

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
      require Logger

      @implementation unquote(implementation)
      @parent unquote(__MODULE__)
      @module __MODULE__
      @module_name "#{@module}"

      # Related Modules.
      @pool @implementation.pool(@module)
      @meta_key Module.concat(@module, "Meta")

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


      @doc """
      Return Banner String With Default Heading
      """
      def banner(msg), do: banner(@module_name, msg)
      defdelegate banner(header, msg), to: @pool

      @doc """
      Verbose setting.
      """
      def verbose(), do: meta()[:verbose]

      @doc """
        key used for persisting meta information.
      """
      def meta_key(), do: @meta_key

      @doc """
      Runtime meta/book keeping data for pool.
      """
      def meta(), do: _imp_meta(@module)
      defdelegate _imp_meta(module), to: @implementation, as: :meta

      @doc """
      Append new entries to meta data (internally a map merge is performed).
      """
      def meta(update), do: _imp_meta(@module, update)
      defdelegate _imp_meta(module, update), to: @implementation, as: :meta

      @doc """
      Initialize meta data for this pool.
      """
      def meta_init(), do: _imp_meta_init(@module)
      defdelegate _imp_meta_init(module), to: @implementation, as: :meta_init

      @doc """
      retrieve effective compile time options/settings for pool.
      """
      def options(), do: @options

      @doc """
      retrieve extended compile time options information for this pool.
      """
      def option_settings(), do: @option_settings

      @doc """
      Current Pool
      """
      defdelegate pool(), to: @pool

      @doc """
      Pool's Worker Supervisor.
      """
      defdelegate pool_worker_supervisor(), to: @pool

      @doc """
      Pool's Server
      """
      defdelegate pool_server(), to: @pool

      @doc """
      Pool's top level supervisor.
      """
      defdelegate pool_supervisor(), to: @pool

      @doc """
      Pool's worker module.
      """
      defdelegate pool_worker(), to: @pool


      @doc """
      Pool's worker state entity.
      """
      defdelegate pool_worker_state_entity(), to: @pool

      @doc """
      OTP start_link entry point.
      """
      def start_link(definition, context), do: _imp_start_link(@module, context, definition) # TODO switch incoming order.
      defdelegate _imp_start_link(module, context, definition), to: @implementation, as: :start_link

      @doc """
      Helper to prepare child OTP definition.
      """
      def child(ref, context), do: _imp_child(@module, ref, context)
      defdelegate _imp_child(module, ref, context), to: @implementation, as: :child

      def child(ref, params, context), do: _imp_child(@module, ref, params, context)
      defdelegate _imp_child(module, ref, params, context), to: @implementation, as: :child

      def child(ref, params, context, options), do: _imp_child(@module, ref, params, context, options)
      defdelegate _imp_child(module, ref, params, context, options), to: @implementation, as: :child

      @doc """
      OTP init entry point.
      """
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


      def pass_through_supervise(a,b), do: supervise(a,b)
      def pass_through_supervisor(a,b,c), do: supervisor(a,b,c)
      def pass_through_worker(a,b,c), do: worker(a,b,c)

      defoverridable [
        _strategy: 0,
        _max_seconds: 0,
        _max_restarts: 0,
        _restart_type: 0,
        banner: 1,
        banner: 2,
        verbose: 0,
        meta_key: 0,
        meta: 0,
        meta: 1,
        meta_init: 0,
        options: 0,
        option_settings: 0,
        pool: 0,
        pool_worker_supervisor: 0,
        pool_server: 0,
        pool_supervisor: 0,
        pool_worker: 0,
        pool_worker_state_entity: 0,
        start_link: 2,
        child: 2,
        child: 3,
        child: 4,
        init: 1,
        handle_call: 3,
        handle_cast: 2,
        handle_info: 2,
        handle_call_catchall: 3,
        handle_cast_catchall: 2,
        handle_info_catchall: 2,

        pass_through_supervise: 2,
        pass_through_supervisor: 3,
        pass_through_worker: 3,
      ]

    end # end quote
  end #end __using__
end
