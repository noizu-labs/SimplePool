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

      @auto_load unquote(MapSet.member?(features, :auto_load))

      @strategy unquote(strategy)
      @max_seconds unquote(max_seconds)
      @max_restarts unquote(max_restarts)

      #----------------------------
      use Noizu.SimplePool.V2.PoolSettingsBehaviour.Inherited, unquote(option_settings)

      @doc """
      Initialize meta data for this pool.
      """
      def meta_init(), do: @implementation.meta_init(@module)

      #--------------------------------

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
        _strategy: 0,
        _max_seconds: 0,
        _max_restarts: 0,
        auto_load: 0,

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