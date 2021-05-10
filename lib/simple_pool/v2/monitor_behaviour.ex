#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.MonitorBehaviour do
  @callback health_check(any, any) :: any
  @callback record_service_event!(any, any, any, any) :: any
  @callback lock!(any, any) :: any
  @callback release!(any, any) :: any

  defmodule Default do
    alias Noizu.ElixirCore.OptionSettings
    alias Noizu.ElixirCore.OptionValue
    alias Noizu.ElixirCore.OptionList
    require Logger

    # @todo alternative solution for specifying features.
    @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection])
    @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection])

    @default_timeout 15_000
    @default_shutdown_timeout 30_000

    def prepare_options(options) do
      settings = %OptionSettings{
        option_settings: %{
          features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
          verbose: %OptionValue{option: :verbose, default: :auto},
          worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
          default_timeout: %OptionValue{option: :default_timeout, default:  Application.get_env(:noizu_simple_pool, :default_timeout, @default_timeout)},
          shutdown_timeout: %OptionValue{option: :shutdown_timeout, default: Application.get_env(:noizu_simple_pool, :default_shutdown_timeout, @default_shutdown_timeout)},
          default_definition: %OptionValue{option: :default_definition, default: :auto},
          log_timeouts: %OptionValue{option: :log_timeouts, default: Application.get_env(:noizu_simple_pool, :default_log_timeouts, true)},
          max_supervisors: %OptionValue{option: :max_supervisors, default: Application.get_env(:noizu_simple_pool, :default_max_supervisors, 100)},
        }
      }
      OptionSettings.expand(settings, options)
    end


    @temporary_core_events MapSet.new([:start, :shutdown])
    def core_events(_pool) do
      # TODO use fast global wrapper around SettingTable
      @temporary_core_events
    end

    def record_service_event!(pool, event, _details, context, _opts) do
      if MapSet.member?(core_events(pool), event) do
        Logger.info(fn() -> {"TODO - write to ServiceEventTable #{inspect event}", Noizu.ElixirCore.CallingContext.metadata(context)} end)
      else
        Logger.info(fn() -> {"TODO - write to DetailedServiceEventTable #{inspect event}", Noizu.ElixirCore.CallingContext.metadata(context)} end)
      end
    end
  end

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.ServerBehaviour.Default)
    option_settings = implementation.prepare_options(options)

    # Temporary Hardcoding
    message_processing_provider = Noizu.SimplePool.V2.MessageProcessingBehaviour.DefaultProvider

    quote do
      use GenServer
      @pool :pending
      use Noizu.SimplePool.V2.SettingsBehaviour.Inherited, unquote([option_settings: option_settings])
      use unquote(message_processing_provider), unquote(option_settings)

      #---------------
      # start_link
      #---------------
      def start_link(server_process \\ :error, definition \\ :default, context \\ nil) do
        # @todo :wip
        GenServer.start_link(__MODULE__, [server_process, definition, context], name: __MODULE__, restart: :permanent)
      end

      #---------------
      # init
      #---------------
      def init([server_process, definition, context] = args) do
        # @todo :wip
        {:ok, %{}}
      end

      def terminate(reason, state) do
        # @todo :wip
        :ok
      end

      def health_check(context, opts \\ %{}), do: :wip
      def record_service_event!(event, details, context, opts \\ %{}) do
        Noizu.SimplePool.V2.MonitorBehaviour.Default.record_service_event!(@pool, event, details, context, opts)
      end

      def lock!(context, opts \\ %{}), do: :wip
      def release!(context, opts \\ %{}), do: :wip


      #===============================================================================================================
      # Overridable
      #===============================================================================================================
      defoverridable [
        start_link: 3,
        init: 1,
        terminate: 2,
        health_check: 2,
        record_service_event!: 4,
        lock!: 2,
        release!: 2
      ]
    end
  end

end
