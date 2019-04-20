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

    quote do
      import unquote(__MODULE__)
      require Logger
      @behaviour Noizu.SimplePool.WorkerBehaviour
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
      use Noizu.SimplePool.V2.PoolSettingsBehaviour.Inherited, unquote([option_settings: option_settings])
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
      ]

    end # end quote
  end #end __using__
end
