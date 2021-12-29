#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerBehaviour do
  @moduledoc """
  Provides worker core functionality

  @note this module is still under heavy development, and is currently merely a copy of the V1 implementation with few structural changes.

  @todo combine InnerStateBehaviour and WorkerBehaviour, expose protocol or behavior method for accessing the Worker.State structure as needed.
  @todo rewrite call handler logic (simplify/cleanup) with a more straight forward path for extending handlers and consistent naming convention.
  """
  require Logger

  @callback delayed_init(any, any) :: any
  @callback schedule_migrate_shutdown(any, any) :: any
  @callback clear_migrate_shutdown(any) :: any
  @callback schedule_inactivity_check(any, any) :: any
  @callback clear_inactivity_check(any) :: any


  defmodule Default do
    alias Noizu.ElixirCore.OptionSettings
    alias Noizu.ElixirCore.OptionValue
    alias Noizu.ElixirCore.OptionList

    @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])
    @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])
    @default_check_interval_ms (1000 * 60 * 5)
    @default_kill_interval_ms (1000 * 60 * 15)
    def prepare_options(options) do
      settings = %OptionSettings{
        option_settings: %{
          features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
          verbose: %OptionValue{option: :verbose, default: :auto},
          worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
          check_interval_ms: %OptionValue{option: :check_interval_ms, default: Application.get_env(:noizu_simple_pool, :default_inactivity_check_interval_ms, @default_check_interval_ms)},
          kill_interval_ms: %OptionValue{option: :kill_interval_ms, default: Application.get_env(:noizu_simple_pool, :default_inactivity_kill_interval_ms, @default_kill_interval_ms)},
        }
      }
      OptionSettings.expand(settings, options)
    end



    def init(pool_worker, {:migrate, ref, initial_state, context}) do

      wm = pool_worker.pool_server().worker_management()
      #server = pool_worker.pool_server()
      #base = pool_worker.pool()


      br = :os.system_time(:millisecond)
      wm.register!(ref, context)
      task = wm.set_node!(ref, context)
      r = Task.yield(task, 75)
      ar = :os.system_time(:millisecond)
      td = ar - br
      cond do
        td > 50 -> Logger.error(fn -> {pool_worker.banner("[Reg Time] - Critical #{__MODULE__} (#{inspect ref } = #{td} milliseconds"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
        td > 25 -> Logger.warn(fn -> {pool_worker.banner("[Reg Time] - Delayed #{__MODULE__} (#{inspect ref } = #{td} milliseconds"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
        td > 15 -> Logger.info(fn -> {pool_worker.banner("[Reg Time] - Slow #{__MODULE__} (#{inspect ref } = #{td} milliseconds"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
        true -> :ok
      end
      # TODO V2 version needed.
      {:ok, %Noizu.SimplePool.Worker.State{extended: %{set_node_task: r || task}, initialized: :delayed_init, worker_ref: ref, inner_state: {:transfer, initial_state}}}
    end

    def init(pool_worker, {ref, context}) do
      wm = pool_worker.pool_server().worker_management()
      #server = pool_worker.pool_server()
      #base = pool_worker.pool()

      br = :os.system_time(:millisecond)
      wm.register!(ref, context)
      task = wm.set_node!(ref, context)
      r = Task.yield(task, 75)
      ar = :os.system_time(:millisecond)
      td = ar - br
      cond do
        td > 50 -> Logger.error(fn -> {pool_worker.banner("[Reg Time] - Critical #{__MODULE__} (#{inspect ref } = #{td} milliseconds"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
        td > 25 -> Logger.warn(fn -> {pool_worker.banner("[Reg Time] - Delayed #{__MODULE__} (#{inspect ref } = #{td} milliseconds"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
        td > 15 -> Logger.info(fn -> {pool_worker.banner("[Reg Time] - Slow #{__MODULE__} (#{inspect ref } = #{td} milliseconds"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
        true -> :ok
      end
      # TODO V2 version needed.
      {:ok, %Noizu.SimplePool.Worker.State{extended: %{set_node_task:  r || task}, initialized: :delayed_init, worker_ref: ref, inner_state: :start}}
    end

    def delayed_init(pool_worker, state, context) do

      # TODO load from meta
      inactivity_check = false
      lazy_load = true

      worker_state_entity = pool_worker.pool_worker_state_entity()
      mod = pool_worker
      #wm = pool_worker.pool_server().worker_management()
      #server = pool_worker.pool_server()
      base = pool_worker.pool()

      ref = state.worker_ref
      ustate = case state.inner_state do
        # @TODO - investigate strategies for avoiding keeping full state in child def. Aka put into state that accepts a transfer/reads a transfer form a table, etc.
        {:transfer, {:state, initial_state, :time, time}} ->
          cut_off = :os.system_time(:second) - 60*15
          if time < cut_off do
            if (mod.verbose()) do
              Logger.info(fn -> {base.banner("INIT/1.stale_transfer#{__MODULE__} (#{inspect ref }"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
            end
            #PRI-0 - disabled until rate limit available - spawn fn -> server.worker_lookup_handler().record_event!(ref, :start, :normal, context, %{}) end
            {initialized, inner_state} = if lazy_load do
              case worker_state_entity.load(ref, context) do
                nil -> {false, nil}
                inner_state -> {true, inner_state}
              end
            else
              {false, nil}
            end
            %Noizu.SimplePool.Worker.State{initialized: initialized, worker_ref: ref, inner_state: inner_state}
          else
            if (mod.verbose()) do
              Logger.info(fn -> {base.banner("INIT/1.transfer #{__MODULE__} (#{inspect ref }"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
            end
            #PRI-0 - disabled until rate limit available - spawn fn -> server.worker_lookup_handler().record_event!(ref, :start, :migrate, context, %{}) end
            {initialized, inner_state} = worker_state_entity.transfer(ref, initial_state.inner_state, context)
            %Noizu.SimplePool.Worker.State{initial_state| initialized: initialized, worker_ref: ref, inner_state: inner_state}
          end

        {:transfer, initial_state} ->
          if (mod.verbose()) do
            Logger.info(fn -> {base.banner("INIT/1.transfer #{__MODULE__} (#{inspect ref }"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
          end
          #PRI-0 - disabled until rate limit available - spawn fn -> server.worker_lookup_handler().record_event!(ref, :start, :migrate, context, %{}) end
          {initialized, inner_state} = worker_state_entity.transfer(ref, initial_state.inner_state, context)
          %Noizu.SimplePool.Worker.State{initial_state| initialized: initialized, worker_ref: ref, inner_state: inner_state}
        :start ->
          if (mod.verbose()) do
            Logger.info(fn -> {base.banner("INIT/1 #{__MODULE__} (#{inspect ref }"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
          end
          #PRI-0 - disabled until rate limit available - spawn fn -> server.worker_lookup_handler().record_event!(ref, :start, :normal, context, %{}) end
          {initialized, inner_state} = if lazy_load do
            case worker_state_entity.load(ref, context) do
              nil -> {false, nil}
              inner_state -> {true, inner_state}
            end
          else
            {false, nil}
          end
          %Noizu.SimplePool.Worker.State{initialized: initialized, worker_ref: ref, inner_state: inner_state}
      end



      if inactivity_check do
        ustate = %Noizu.SimplePool.Worker.State{ustate| last_activity: :os.system_time(:seconds)}
        ustate = mod.schedule_inactivity_check(nil, ustate)
        ustate
      else
        ustate
      end
    end

    def schedule_inactivity_check(check_interval_ms, context, state) do
      {:ok, t_ref} = :timer.send_after(check_interval_ms, self(), {:i, {:activity_check, state.worker_ref}, context})
      put_in(state, [Access.key(:extended), :t_ref], t_ref)
    end

    def clear_inactivity_check(state) do
      case Map.get(state.extended, :t_ref) do
        nil -> state
        t_ref ->
          :timer.cancel(t_ref)
          put_in(state, [Access.key(:extended), :t_ref], nil)
      end
    end

    def schedule_migrate_shutdown(migrate_shutdown_interval_ms, context, state) do
      {:ok, mt_ref} = :timer.send_after(migrate_shutdown_interval_ms, self(), {:i, {:migrate_shutdown, state.worker_ref}, context})
      put_in(state, [Access.key(:extended), :mt_ref], mt_ref)
    end

    def clear_migrate_shutdown(state) do
      case Map.get(state.extended, :mt_ref) do
        nil -> state
        mt_ref ->
          :timer.cancel(mt_ref)
          put_in(state, [Access.key(:extended), :mt_ref], nil)
      end
    end

  end


  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.WorkerBehaviour.Default)
    option_settings = implementation.prepare_options(options)
    options = option_settings.effective_options
    features = MapSet.new(options.features)
    verbose = options.verbose


    message_processing_provider = Noizu.SimplePool.V2.MessageProcessingBehaviour.DefaultProvider
    quote do
      import unquote(__MODULE__)
      require Logger
      #@behaviour Noizu.SimplePool.WorkerBehaviour
      use GenServer

      @check_interval_ms (unquote(options.check_interval_ms))
      @kill_interval_s (unquote(options.kill_interval_ms)/1000)
      @migrate_shutdown_interval_ms (5_000)
      @migrate_shutdown unquote(MapSet.member?(features, :migrate_shutdown))
      @inactivity_check unquote(MapSet.member?(features, :inactivity_check))
      @lazy_load unquote(MapSet.member?(features, :lazy_load))
      @base_verbose (unquote(verbose))
      #--------------------------------------------
      @option_settings :override
      @options :override
      @pool_worker_state_entity :override
      use Noizu.SimplePool.V2.SettingsBehaviour.Inherited, unquote([option_settings: option_settings])
      use unquote(message_processing_provider), unquote(option_settings)
      #--------------------------------------------



      def start_link(ref, context) do
        verbose() && Logger.info(fn -> {banner("START_LINK/2 #{__MODULE__} (#{inspect ref})"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
        GenServer.start_link(__MODULE__, {ref, context})
      end

      def start_link(ref, migrate_args, context) do
        verbose() && Logger.info(fn -> {banner("START_LINK/3 #{__MODULE__} (#{inspect migrate_args})"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
        GenServer.start_link(__MODULE__, {:migrate, ref, migrate_args, context})
      end

      def terminate(reason, state) do
        verbose() && Logger.info(fn -> banner("TERMINATE #{__MODULE__} (#{inspect state.worker_ref}\n Reason: #{inspect reason}") end)
        @pool_worker_state_entity.terminate_hook(reason, Noizu.SimplePool.WorkerBehaviourDefault.clear_inactivity_check(state))
      end


      def init(arg) do
        Noizu.SimplePool.V2.WorkerBehaviour.Default.init(__MODULE__, arg)
      end


      def delayed_init(state, context) do
        Noizu.SimplePool.V2.WorkerBehaviour.Default.delayed_init(__MODULE__, state, context)
      end
      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------
      def schedule_migrate_shutdown(context, state) do
        Noizu.SimplePool.V2.WorkerBehaviour.Default.schedule_migrate_shutdown(@migrate_shutdown_interval_ms, context, state)
      end

      def clear_migrate_shutdown(state) do
        Noizu.SimplePool.V2.WorkerBehaviour.Default.clear_migrate_shutdown(state)
      end

      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------
      def schedule_inactivity_check(context, state) do
        Noizu.SimplePool.V2.WorkerBehaviour.Default.schedule_inactivity_check(@check_interval_ms, context, state)
      end

      def clear_inactivity_check(state) do
        Noizu.SimplePool.V2.WorkerBehaviour.Default.clear_inactivity_check(state)
      end

      #------------------------------------------------------------------------
      # Infrastructure Provided Worker Calls
      #------------------------------------------------------------------------

      #-----------------------------
      # fetch!/4
      #-----------------------------
      def fetch!(state, args, from, context), do: fetch!(state, args, from, context, nil)

      #-----------------------------
      # fetch!/5
      #-----------------------------
      def fetch!(state, {:state}, _from, _context, _options), do: {:reply, state, state}
      def fetch!(state, {:default}, _from, _context, _options), do: {:reply, state, state}
      def fetch!(state, {:inner_state}, _from, _context, _options), do: {:reply, state.inner_state, state}
      def fetch!(state, {:process}, _from, _context, _options), do: {:reply, {is_map(state.inner_state) && Noizu.ERP.ref(state.inner_state) || state.inner_state, self(), node()}, state}
      def fetch!(_state, command, _from, _context, _options) do
        IO.puts "[[[UNHANDLED FETCH COMMAND: #{inspect command}]]]"
        nil  # all inner_state implementations
      end

      #-----------------------------
      # ping/5
      #-----------------------------
      def ping(state, _args, _from, _context, _options \\ nil), do: {:reply, :pong, state}

      #-----------------------------
      # save!/5
      #-----------------------------
      def save!(state, _args, _from, _context, _opts \\ nil) do
        Logger.error("#{__MODULE__}.save! Required")
        {:reply, :nyi, state}
      end

      #-----------------------------
      # reload!/5
      #-----------------------------
      def reload!(state, _args, _from, context, opts \\ nil) do
        worker_state_entity = __MODULE__.pool_worker_state_entity()
        inner_state = cond do
          state.initialized -> worker_state_entity.reload(state.inner_state, context, opts)
          :else -> worker_state_entity.load(state.worker_ref, context, opts)
        end
        {:reply, inner_state, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, initialized: inner_state && true || false}}
      end

      #-----------------------------
      # load!/5
      #-----------------------------
      def load!(state, _args, _from, context, opts \\ nil) do
        worker_state_entity = __MODULE__.pool_worker_state_entity()
        inner_state = worker_state_entity.load(state.worker_ref, context, opts)
        state = %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, initialized: inner_state && true || false}
        {:reply, inner_state, state}
      end

      #-----------------------------
      # shutdown!/5
      #-----------------------------
      def shutdown!(state, _args, _from, context, _opts \\ nil) do
        Logger.error("#{__MODULE__}.shutdown NYI", Noizu.ElixirCore.CallingContext.metadata(context))
        {:reply, :nyi, state}
      end

      #-----------------------------
      # migrate!/5
      #-----------------------------
      def migrate!(state, {ref, rebase} = _args, _from, context, _opts \\ nil) do
        Logger.error("#{__MODULE__}.migrate! NYI", Noizu.ElixirCore.CallingContext.metadata(context))
        {:reply, :nyi, state}
      end

      #-----------------------------
      # health_check!/5
      #-----------------------------
      def health_check!(state, _args, _from, context, _opts \\ nil) do
        Logger.error("#{__MODULE__}.health_check! NYI", Noizu.ElixirCore.CallingContext.metadata(context))
        {:reply, :nyi, state}
      end

      #-----------------------------
      # kill!/5
      #-----------------------------
      def kill!(state, _args, _from, context, _opts \\ nil) do
        {:stop, :shutdown, :user_shutdown, state}
      end

      #-----------------------------
      # crash!/5
      #-----------------------------
      def crash!(state, _args, _from, _context, _opts \\ nil) do
        throw "#{__MODULE__} - Forced Crash!"
      end


      #-----------------------------
      # inactivity_check/5
      #-----------------------------
      def inactivity_check(state, _args, _from, context, _opts \\ nil) do
        Logger.error("#{__MODULE__}.inactivity_check! NYI", Noizu.ElixirCore.CallingContext.metadata(context))
        {:noreply, state}
      end


      #------------------------------------------------------------------------
      # Infrastructure provided call router
      #------------------------------------------------------------------------
      def call_router_internal__default({:passive, envelope}, from, state), do: call_router_internal__default(envelope, from, state)
      def call_router_internal__default({:spawn, envelope}, from, state), do: call_router_internal__default(envelope, from, state)
      def call_router_internal__default(envelope, from, state) do
        case envelope do
          # fetch
          {:s, {:fetch!, args}, context} -> fetch!(state, args, from, context)
          {:s, {:fetch!, args, opts}, context} -> fetch!(state, args, from, context, opts)

          # ping!
          {:s, {:ping, args}, context} -> ping(state, args, from, context)
          {:s, {:ping, args, opts}, context} -> ping(state, args, from, context, opts)

          # health_check!
          {:s, {:health_check!, args}, context} -> health_check!(state, args, from, context)
          {:s, {:health_check!, args, opts}, context} -> health_check!(state, args, from, context, opts)

          # kill!
          {:s, {:kill!, args}, context} -> kill!(state, args, from, context)
          {:s, {:kill!, args, opts}, context} -> kill!(state, args, from, context, opts)

          # crash!
          {:s, {:crash!, args}, context} -> crash!(state, args, from, context)
          {:s, {:crash!, args, opts}, context} -> crash!(state, args, from, context, opts)

          # save!
          {:s, {:save!, args}, context} -> save!(state, args, from, context)
          {:s, {:save!, args, opts}, context} -> save!(state, args, from, context, opts)

          # reload!
          {:s, {:reload!, args}, context} -> reload!(state, args, from, context)
          {:s, {:reload!, args, opts}, context} -> reload!(state, args, from, context, opts)

          # load!
          {:s, {:load!, args}, context} -> load!(state, args, from, context)
          {:s, {:load!, args, opts}, context} -> load!(state, args, from, context, opts)

          # shutdown
          {:s, {:shutdown!, args}, context} -> shutdown!(state, args, from, context)
          {:s, {:shutdown!, args, opts}, context} -> shutdown!(state, args, from, context, opts)

          # migrate
          {:s, {:migrate!, args}, context} -> migrate!(state, args, from, context)
          {:s, {:migrate!, args, opts}, context} -> migrate!(state, args, from, context, opts)

          _ -> nil
        end
      end
      def call_router_internal(envelope, from, state), do: call_router_internal__default(envelope, from, state)


      #----------------------------
      #
      #----------------------------
      def cast_router_internal__default(envelope, state) do
        r = call_router_internal(envelope, :cast, state)
        r && as_cast(r)
      end
      def cast_router_internal(envelope, state), do: cast_router_internal__default(envelope, state)

      #----------------------------
      #
      #----------------------------
      def info_router_internal__default({:passive, envelope}, state), do: info_router_internal__default(envelope, state)
      def info_router_internal__default({:spawn, envelope}, state), do: info_router_internal__default(envelope, state)
      def info_router_internal__default(envelope, state) do
        case envelope do
          {:i, {:inactivity_check, args}, context} -> inactivity_check(state, args, :info, context) |> as_cast()
          {:i, {:inactivity_check, args, opts}, context} -> inactivity_check(state, args, :info, context, opts) |> as_cast()
          _ -> nil
        end
      end
      def info_router_internal(envelope, state), do: info_router_internal__default(envelope, state)

      # Delegate uncaught calls into inner state.
      def call_router_catchall(envelope, from, state) do
        Noizu.SimplePool.V2.MessageProcessingBehaviour.Default.__delegate_call_handler(__MODULE__, envelope, from, state)
      end
      def cast_router_catchall(envelope, state) do
        Noizu.SimplePool.V2.MessageProcessingBehaviour.Default.__delegate_cast_handler(__MODULE__, envelope, state)
      end
      def info_router_catchall(envelope, state) do
        Noizu.SimplePool.V2.MessageProcessingBehaviour.Default.__delegate_info_handler(__MODULE__, envelope, state)
      end


      #===============================================================================================================
      # Overridable
      #===============================================================================================================
      defoverridable [
        start_link: 2,
        start_link: 3,
        terminate: 2,
        init: 1,
        delayed_init: 2,
        schedule_migrate_shutdown: 2,
        clear_migrate_shutdown: 1,
        schedule_inactivity_check: 2,
        clear_inactivity_check: 1,

        # Infrastructure Provided Worker Methods
        fetch!: 4,
        fetch!: 5,
        ping: 5,
        save!: 5,
        reload!: 5,
        load!: 5,
        shutdown!: 5,
        migrate!: 5,
        health_check!: 5,
        kill!: 5,
        crash!: 5,
        inactivity_check: 5,

        # Routing for Infrastructure Provided Worker Methods
        call_router_internal: 3,
        info_router_internal: 2,
        cast_router_internal: 2,

        # Catch All (For worker delegates to inner_state entity)
        call_router_catchall: 3,
        cast_router_catchall: 2,
        info_router_catchall: 2,
      ]

    end # end quote
  end #end __using__
end
