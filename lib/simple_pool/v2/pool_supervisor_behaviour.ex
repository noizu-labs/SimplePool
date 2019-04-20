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

  defmodule Default do
    alias Noizu.ElixirCore.OptionSettings
    alias Noizu.ElixirCore.OptionValue
    alias Noizu.ElixirCore.OptionList
    require Logger

    @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection])
    @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection])

    @default_max_seconds (1)
    @default_max_restarts (1_000_000)
    @default_strategy (:one_for_one)

    #------------
    #
    #------------
    def prepare_options(options) do
      settings = %OptionSettings{
        option_settings: %{
          features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
          verbose: %OptionValue{option: :verbose, default: :auto},
          max_restarts: %OptionValue{option: :max_restarts, default: Application.get_env(:noizu_simple_pool, :pool_max_restarts, @default_max_restarts)},
          max_seconds: %OptionValue{option: :max_seconds, default: Application.get_env(:noizu_simple_pool, :pool_max_seconds, @default_max_seconds)},
          strategy: %OptionValue{option: :strategy, default: Application.get_env(:noizu_simple_pool, :pool_strategy, @default_strategy)}
        }
      }

      OptionSettings.expand(settings, options)
    end

    #------------
    #
    #------------
    def start_link(module, context, definition \\ :auto) do
      if module.verbose() do
        Logger.info(fn ->
          header = "#{module}.start_link"
          body = "args: #{inspect %{context: context, definition: definition}}"
          metadata = Noizu.ElixirCore.CallingContext.metadata(context)
          {module.banner(header, body), metadata}
        end)
      end
      case Supervisor.start_link(module, [context], [{:name, module}, {:restart, :permanent}]) do
        {:ok, sup} ->
          Logger.info(fn ->  {"#{module}.start_link Supervisor Not Started. #{inspect sup}", Noizu.ElixirCore.CallingContext.metadata(context)} end)
          module.start_children(module, context, definition)
          {:ok, sup}
        {:error, {:already_started, sup}} ->
          Logger.info(fn -> {"#{module}.start_link Supervisor Already Started. Handling Unexpected State.  #{inspect sup}" , Noizu.ElixirCore.CallingContext.metadata(context)} end)
          module.start_children(module, context, definition)
          {:ok, sup}
      end
    end

    #------------
    #
    #------------
    def start_children(module, sup, context, definition \\ :auto) do
      if module.verbose() do
        Logger.info(fn -> {
                            module.banner("#{module}.start_children",
                              """

                              #{module} START_CHILDREN
                              Options: #{inspect module.options()}
                              worker_supervisor: #{module.pool_worker_supervisor()}
                              worker_server: #{module.pool_server()}
                              definition: #{inspect definition}
                              """),
                            Noizu.ElixirCore.CallingContext.metadata(context)
                          }
        end)
      end

      # @TODO - move into runtime meta.
      max_seconds = module._max_seconds()
      max_restarts = module._max_restarts()

      # Start Worker Supervisor
      s = case Supervisor.start_child(sup, module.pass_through_worker(module.pool_worker_supervisor(), [definition, context],  [restart: :permanent, max_restarts: max_restarts, max_seconds: max_seconds])) do
        {:ok, pid} ->
          {:ok, pid}
        {:error, {:already_started, process2_id}} ->
          Supervisor.restart_child(module, process2_id)
        error ->
          Logger.error(fn ->
            {
              """

              #{module}.start_children(1) #{inspect module.pool_worker_supervisor()} Already Started. Handling unexpected state.
              #{inspect error}
              """, Noizu.ElixirCore.CallingContext.metadata(context)}
          end)
          :error
      end

      # Start Server Supervisor
      s = case Supervisor.start_child(sup, module.pass_through_worker(module.pool_server(), [definition, context], [restart: :permanent, max_restarts: max_restarts, max_seconds: max_seconds])) do
        {:ok, pid} ->
          {:ok, pid}
        {:error, {:already_started, process2_id}} ->
          Supervisor.restart_child(module, process2_id)
        error ->
          Logger.error(fn ->
            {
              """

              #{module}.start_children(1) #{inspect module.pool_server()} Already Started. Handling unexpected state.
              #{inspect error}
              """, Noizu.ElixirCore.CallingContext.metadata(context)}
          end)
          :error
      end
      if s != :error && module.auto_load() do
        spawn fn -> module.pool_sever().load(context, module.options()) end
      end
      s
    end # end start_children

    def init(module, [context] = arg) do
      if module.verbose() || true do
        Logger.warn(fn -> {module.banner("#{module} INIT", "args: #{inspect arg}"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
      end
      strategy = module._strategy()
      max_seconds = module._max_seconds()
      max_restarts = module._max_restarts()
      module.pass_through_supervise([], [{:strategy, strategy}, {:max_restarts, max_restarts}, {:max_seconds, max_seconds}, {:restart, :permanent}])
    end

  end

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.PoolSupervisorBehaviour.Default)
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
      use Noizu.SimplePool.V2.PoolSettingsBehaviour.Inherited, unquote([option_settings: option_settings])
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

      #@doc """
      #Start worker supervisors.
      #"""
      #def start_worker_supervisors(sup, context, definition), do: _imp_start_worker_supervisors(@module, sup, context, definition)
      #defdelegate _imp_start_worker_supervisors(module, sup, context, definition), to: @implementation, as: :start_worker_supervisors

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

      def handle_call_catchall(msg, from, s), do: throw :pri0_handle_call_catchall
      def handle_cast_catchall(msg, s), do: throw :pri0_handle_cast_catchall
      def handle_info_catchall(msg, s), do: throw :pri0_handle_info_catchall

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
        #start_worker_supervisors: 3,
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