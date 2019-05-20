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
        verbose() && Logger.info(fn -> banner("START_LINK/2 #{__MODULE__} (#{inspect ref})") end)
        GenServer.start_link(__MODULE__, {ref, context})
      end

      def start_link(ref, migrate_args, context) do
        verbose() && Logger.info(fn -> banner("START_LINK/3 #{__MODULE__} (#{inspect migrate_args})") end)
        GenServer.start_link(__MODULE__, {:migrate, ref, migrate_args, context})
      end

      def terminate(reason, state) do
        verbose() && Logger.info(fn -> banner("TERMINATE #{__MODULE__} (#{inspect state.worker_ref}\n Reason: #{inspect reason}") end)
        @pool_worker_state_entity.terminate_hook(reason, Noizu.SimplePool.WorkerBehaviourDefault.clear_inactivity_check(state))
      end


      def init(arg) do
        Noizu.SimplePool.WorkerBehaviourDefault.init({__MODULE__, pool_server(), pool(), pool_worker_state_entity(), @inactivity_check, @lazy_load}, arg)
      end


      def delayed_init(state, context) do
        Noizu.SimplePool.WorkerBehaviourDefault.delayed_init({__MODULE__, pool_server(), pool(), pool_worker_state_entity(), @inactivity_check, @lazy_load}, state, context)
      end
      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------
      def schedule_migrate_shutdown(context, state) do
        Noizu.SimplePool.WorkerBehaviourDefault.schedule_migrate_shutdown(@migrate_shutdown_interval_ms, context, state)
      end

      def clear_migrate_shutdown(state) do
        Noizu.SimplePool.WorkerBehaviourDefault.clear_migrate_shutdown(state)
      end

      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------
      def schedule_inactivity_check(context, state) do
        Noizu.SimplePool.WorkerBehaviourDefault.schedule_inactivity_check(@check_interval_ms, context, state)
      end

      def clear_inactivity_check(state) do
        Noizu.SimplePool.WorkerBehaviourDefault.clear_inactivity_check(state)
      end


      #------------------------------------------------------------------------
      # Infrastructure Provided Worker Calls
      #------------------------------------------------------------------------
      def fetch(state, :state, _from, _context), do: {:reply, state, state}
      def fetch(state, :process, _from, _context), do: {:reply, {self(), node()}, state}
      def ping!(state, _from, _context), do: {:reply, :pong, state}

      def save!(state, _from, _context, _opts) do
        Logger.error("#{__MODULE__}.save! NYI")
        {:reply, :nyi, state}
      end
      def reload!(state, _from, _context, _opts) do
        Logger.error("#{__MODULE__}.reload! NYI")
        {:reply, :nyi, state}
      end
      def load(state, _from, _context, _opts) do
        Logger.error("#{__MODULE__}.load NYI")
        {:reply, :nyi, state}
      end
      def shutdown(state, _from, _context, _opts) do
        Logger.error("#{__MODULE__}.shutdown NYI")
        {:reply, :nyi, state}
      end
      def migrate!(state, _ref, _rebase, _from, _context, _opts) do
        Logger.error("#{__MODULE__}.migrate! NYI")
        {:reply, :nyi, state}
      end
      def health_check!(state, _from, _context, _opts) do
        Logger.error("#{__MODULE__}.health_check! NYI")
        {:reply, :nyi, state}
      end
      def kill!(state, _from, _context) do
        Logger.error("#{__MODULE__}.kill! NYI")
        {:reply, :nyi, state}
      end
      def crash!(state, _from, _context, _opts) do
        Logger.error("#{__MODULE__}.crash! NYI")
        {:reply, :nyi, state}
      end
      def activity_check(state, _ref, _context) do
        Logger.error("#{__MODULE__}.activity_check NYI")
        #NYI
        {:noreply, state}
      end

      #------------------------------------------------------------------------
      # Infrastructure provided call router
      #------------------------------------------------------------------------
      def call_router_internal(envelope, from, state) do
        case envelope do
          {:s, {:fetch, :state}, context} -> fetch(state, :state, from, context)
          {:s, {:fetch, :process}, context} -> fetch(state, :process, from, context)
          {:s, :ping!, context} -> ping!(state, from, context)

          {:s, {:health_check!, opts}, context} -> health_check!(state, from, context, opts)
          {:s, :kill!, context} -> kill!(state, from, context)
          {:s, {:crash!, opts}, context} -> crash!(state, from, context, opts)

          {:s, {:save!, opts}, context} -> save!(state, from, context, opts)
          {:s, {:reload!, opts}, context} -> reload!(state, from, context, opts)
          {:s, {:load, opts}, context} -> load(state, from, context, opts)
          {:s, {:shutdown, opts}, context} -> shutdown(state, from, context, opts)
          {:s, {:migrate!, ref, rebase, opts}, context} -> migrate!(state, ref, rebase, from, context, opts)
          _ -> nil
        end
      end

      def cast_router_internal(envelope, state) do
        case envelope do
          # Todo include kill! options to standardize function signatures.
          {:s, :kill!, context} -> kill!(state, :cast, context) |> as_cast()
          {:s, {:crash!, opts}, context} -> crash!(state, :cast, context, opts) |> as_cast()
          {:s, {:save!, opts}, context} -> save!(state, :cast, context, opts) |> as_cast()
          {:s, {:reload!, opts}, context} -> reload!(state, :cast, context, opts) |> as_cast()
          {:s, {:load, opts}, context} -> load(state, :cast, context, opts) |> as_cast()
          {:s, {:shutdown, opts}, context} -> shutdown(state, :cast, context, opts) |> as_cast()
          {:s, {:migrate!, ref, rebase, opts}, context} -> migrate!(state, ref, rebase, :cast, context, opts) |> as_cast()
          _ -> nil
        end
      end

      def info_router_internal(envelope, state) do
        case envelope do
          {:i, {:activity_check, ref}, context} -> activity_check(state, ref, context)
          _ -> nil
        end
      end


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
        fetch: 4,
        ping!: 3,
        save!: 4,
        reload!: 4,
        load: 4,
        shutdown: 4,
        migrate!: 6,
        health_check!: 4,
        kill!: 3,
        crash!: 4,
        activity_check: 3,

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
