#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.PoolSupervisorBehaviour do

  @moduledoc """
  PoolSupervisorBehaviour provides the implementation for the top level node in a Pools OTP tree.
  The Pool Supervisor is responsible to monitoring the ServerPool and WorkerSupervisors (which in turn monitor workers)

  @todo Implement a top level WorkerSupervisor that in turn supervises children supervisors.
  """

  @callback option_settings() :: Map.t
  @callback start_link(any, any) :: any
  @callback start_children(any, any, any) :: any

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.PoolSupervisor.DefaultImplementation)
    option_settings = implementation.prepare_options(options)
    options = option_settings.effective_options

    max_restarts = options.max_restarts
    max_seconds = options.max_seconds
    strategy = options.strategy
    features = MapSet.new(options.features)


    quote do
      @behaviour Noizu.SimplePool.V2.PoolSupervisorBehaviour
      use Supervisor
      require Logger
      @implementation unquote(implementation)
      @parent unquote(__MODULE__)
      @module __MODULE__
      @module_name "#{@module}"

      @auto_load unquote(MapSet.member?(features, :auto_load))

      # Related Modules.
      @pool @implementation.pool(@module)
      @meta_key Module.concat(@module, "Meta")

      @options unquote(Macro.escape(options))
      @option_settings unquote(Macro.escape(option_settings))

      @strategy unquote(strategy)
      @max_seconds unquote(max_seconds)
      @max_restarts unquote(max_restarts)

      @doc """
      Return Banner String With Default Heading
      """
      def banner(msg), do: banner(@module_name, msg)

      @doc """
      Return Banner String With Custom Heading
      """
      defdelegate banner(header, msg), to: @pool

      #-------------------
      # @TODO move these into a single runtime_options/otp_options or similar method.
      #-------------------
      def _strategy(), do: @strategy
      def _max_seconds(), do: @max_seconds
      def _max_restarts(), do: @max_restarts

      @doc """
      Auto load setting for pool.
      """
      def auto_load(), do: @auto_load

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
      start_link OTP entry point.
      """
      def start_link(context, definition \\ :auto), do: _imp_start_link(@module, context, definition)
      defdelegate _imp_start_link(module, context, definition), to: @implementation, as: :start_link

      @doc """
      Start supervisor's children.
      """
      def start_children(sup, context, definition \\ :auto), do: _imp_start_children(@module, sup, context, definition)
      defdelegate _imp_start_children(module, sup, context, definition), to: @implementation, as: :start_children

      @doc """
      Start worker supervisors.
      """
      def start_worker_supervisors(sup, context, definition), do: _imp_start_worker_supervisors(@module, sup, context, definition)
      defdelegate _imp_start_worker_supervisors(module, sup, context, definition), to: @implementation, as: :start_worker_supervisors

      @doc """
      OTP Init entry point.
      """
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


      def pass_through_supervise(a,b), do: supervise(a,b)
      def pass_through_supervisor(a,b,c), do: supervisor(a,b,c)
      def pass_through_worker(a,b,c), do: worker(a,b,c)

      defoverridable [
        banner: 1,
        banner: 2,
        _strategy: 0,
        _max_seconds: 0,
        _max_restarts: 0,
        auto_load: 0,
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
        pool_worker: 0,
        pool_worker_state_entity: 0,
        start_link: 2,
        start_children: 3,
        start_worker_supervisors: 3,
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