#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.ServerBehaviour do
  @moduledoc """
  The ServerBehaviour provides the entry point for interacting with worker processes.
  It manages worker process creation and routing calls to the correct process/node/worker supervisor.

  For example the ChatRoomPool.Server would have methods such as  send_message(room_ref, msg, context) which would in turn
  forward a call into the supervisor responsible for room_ref.

  @todo break out core functionality (like routing) into sub modules which in turn are populated with use calls to their respective providers.
  This will allow us to design modules with completely different implementations and function signatures and provide a nice function access hierarchy.
  """

  require Logger

  @callback fetch(any, any, any, any) :: any
  @callback save!(any, any, any) :: any
  @callback save_async!(any, any, any) :: any
  @callback reload!(any, any, any) :: any
  @callback reload_async!(any, any, any) :: any
  @callback ping!(any, any, any) :: any
  @callback kill!(any, any, any) :: any
  @callback crash!(any, any, any) :: any
  @callback health_check!(any, any) :: any
  @callback health_check!(any, any, any) :: any
  @callback health_check!(any, any, any, any) :: any


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

    def meta_init(module) do
      options = module.options()
      %{
        verbose: meta_init_verbose(module, options),
        default_definition: meta_init_default_definition(module, options),
      }
    end

    defp meta_init_verbose(module, options) do
      options.verbose == :auto && module.pool().verbose() || options.verbose
    end

    defp meta_init_default_definition(module, options) do
      a_s = Application.get_env(:noizu_simple_pool, :definitions, %{})
      template = %Noizu.SimplePool.MonitoringFramework.Service.Definition{
        identifier: {node(), module.pool()},
        server: node(),
        pool: module.pool_server(),
        supervisor: module.pool(),
        time_stamp: DateTime.utc_now(),
        hard_limit: 0, # TODO need defaults logic here.
        soft_limit: 0,
        target: 0,
      }

      default_definition = case options.default_definition do
        :auto ->
          case a_s[module.pool()] || a_s[:default] do
            d = %Noizu.SimplePool.MonitoringFramework.Service.Definition{} ->
              %{d|
                identifier: d.identifier || template.identifier,
                server: d.server || template.server,
                pool: d.pool || template.pool,
                supervisor: d.supervisor || template.supervisor
              }

            d = %{} ->
              %{template|
                identifier: Map.get(d, :identifier) || template.identifier,
                server: Map.get(d, :server) || template.server,
                pool: Map.get(d, :pool) || template.pool,
                supervisor: Map.get(d, :supervisor) || template.supervisor,
                hard_limit: Map.get(d, :hard_limit) || template.hard_limit,
                soft_limit: Map.get(d, :soft_limit) || template.soft_limit,
                target: Map.get(d, :target) || template.target,
              }

            _ ->
              # @TODO raise, log, etc.
              template
          end
        d = %Noizu.SimplePool.MonitoringFramework.Service.Definition{} ->
          %{d|
            identifier: d.identifier || template.identifier,
            server: d.server || template.server,
            pool: d.pool || template.pool,
            supervisor: d.supervisor || template.supervisor
          }

        d = %{} ->
          %{template|
            identifier: Map.get(d, :identifier) || template.identifier,
            server: Map.get(d, :server) || template.server,
            pool: Map.get(d, :pool) || template.pool,
            supervisor: Map.get(d, :supervisor) || template.supervisor,
            hard_limit: Map.get(d, :hard_limit) || template.hard_limit,
            soft_limit: Map.get(d, :soft_limit) || template.soft_limit,
            target: Map.get(d, :target) || template.target,
          }

        _ ->
          # @TODO raise, log, etc.
          template
      end
    end
  end

  #=================================================================
  #=================================================================
  # @__using__
  #=================================================================
  #=================================================================
  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.Server.DefaultImplementation)
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.ServerBehaviour.Default)
    option_settings = implementation.prepare_options(options)

    # Temporary Hardcoding
    router_provider = Noizu.SimplePool.V2.RouterBehaviour
    worker_management_provider = Noizu.SimplePool.V2.WorkerManagementBehaviour
    service_management_provider = Noizu.SimplePool.V2.ServiceManagementBehaviour
    message_processing_provider = Noizu.SimplePool.V2.MessageProcessingBehaviour
    quote do
      # todo option value
      @timeout 30_000
      @implementation unquote(implementation)
      @behaviour Noizu.SimplePool.V2.ServerBehaviour
      alias Noizu.SimplePool.Worker.Link
      alias Noizu.SimplePool.Server.EnvironmentDetails
      alias Noizu.SimplePool.Server.State
      use GenServer
      require Logger

      #----------------------------------------------------------
      @option_settings :overide
      use Noizu.SimplePool.V2.PoolSettingsBehaviour.Inherited, unquote([option_settings: option_settings])
      #----------------------------------------------------------

      #----------------------------------------------------------
      use unquote(message_processing_provider), unquote(option_settings)
      #----------------------------------------------------------


      #----------------------------------------------------------
      defmodule Router do
        use unquote(router_provider), unquote(option_settings)
      end
      #----------------------------------------------------------

      #----------------------------------------------------------
      defmodule WorkerManagement do
        use unquote(worker_management_provider), unquote(option_settings)
      end
      #----------------------------------------------------------

      #----------------------------------------------------------
      defmodule ServiceManagement do
        use unquote(service_management_provider), unquote(option_settings)
      end
      #----------------------------------------------------------


      @doc """
      Initialize meta data for this pool. (override default provided by PoolSettingsBehaviour)
      """
      def meta_init(), do: @implementation.meta_init(__MODULE__)

      #---------------
      # start_link
      #---------------
      def start_link(definition \\ :default, context \\ nil) do
        final_definition = definition == :default && __MODULE__.ServiceManagement.default_definition() || definition
        if verbose() do
          Logger.info(fn ->
            default_snippet = (definition == :default) && " (:default)" || ""
            {banner("START_LINK #{__MODULE__} (#{inspect pool_server()}@#{inspect self()})\ndefinition#{default_snippet}: #{inspect final_definition}"), Noizu.ElixirCore.CallingContext.metadata(context)}
          end)
        end
        GenServer.start_link(__MODULE__, [final_definition, context], name: __MODULE__, restart: :permanent)
      end

      #---------------
      # init
      #---------------
      def init([definition, context] = args) do
        verbose() && Logger.info(fn -> {banner("INIT #{__MODULE__} (#{inspect pool_server()}@#{inspect self()})\n args: #{inspect args, pretty: true}"), Noizu.ElixirCore.CallingContext.metadata(context) } end)

        # @TODO we can avoid this jump by directly delegating to server_provider() and updating server_prover to fetch option_settings on its own.
        #module.server_provider().init(module, :deprecated, definition, context, module.option_settings())

        #server.enable_server!(node())
        #options = module.option_settings()
        # TODO load real effective
        effective = %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{
          identifier: {node(), pool()},
          time_stamp: DateTime.utc_now(),
          status: :online,
          directive: :init,
          definition: definition,
        }

        state = %State{
          worker_supervisor: :deprecated,
          service: pool_server(),
          status_details: :pending,
          extended: %{},
          environment_details: %EnvironmentDetails{definition: definition, effective: effective, status: :init},
          options: @option_settings
        }

        __MODULE__.ServiceManagement.record_service_event!(:start, %{definition: definition, options: @option_settings}, context, %{})
        {:ok, state}
      end

      def terminate(reason, state) do
        context = nil
        __MODULE__.ServiceManagement.record_service_event!(:terminate, %{reason: reason}, context, @option_settings)
        Logger.warn( fn -> banner("Terminate #{inspect state, pretty: true}\nReason: #{inspect reason}") end)
        #this.server.disable_server!(node())
        :ok
      end

      #---------------------------------------------------------
      # Built in Worker Convenience Methods.
      #---------------------------------------------------------
      @doc """
      Request information about a worker.
      """
      def fetch(ref, request \\ :state, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call!(ref, {:fetch, request}, context, options)
      end

      @doc """
      Tell a worker to save its state.
      """
      def save!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call!(identifier, :save!, context, options)
      end

      @doc """
      Tell a worker to save its state, do not wait for response.
      """
      def save_async!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast!(identifier, :save!, context, options)
      end

      @doc """
      Tell a worker to reload its state.
      """
      def reload!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call!(identifier, {:reload!, options}, context, options)
      end

      @doc """
      Tell a worker to reload its state, do not wait for a response.
      """
      def reload_async!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast!(identifier, {:reload!, options}, context, options)
      end

      @doc """
      Ping worker.
      """
      def ping!(identifier, context \\ nil, options \\ %{}) do
        timeout = options[:timeout] || @timeout
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call(identifier, :ping!, context, options, timeout)
      end

      @doc """
      Send worker a kill request.
      """
      def kill!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast!(identifier, :kill!, context, options)
      end

      @doc """
      Send a worker a crash (throw error) request.
      """
      def crash!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast!(identifier, :crash!, context, options)
      end

      @doc """
      Request a health report from worker.
      """
      def health_check!(identifier, %Noizu.ElixirCore.CallingContext{} = context) do
        __MODULE__.Router.s_call!(identifier, {:health_check!, %{}}, context)
      end
      def health_check!(identifier, health_check_options, %Noizu.ElixirCore.CallingContext{} = context) do
        __MODULE__.Router.s_call!(identifier, {:health_check!, health_check_options}, context)
      end
      def health_check!(identifier, health_check_options, %Noizu.ElixirCore.CallingContext{} = context, options) do
        __MODULE__.Router.s_call!(identifier, {:health_check!, health_check_options}, context, options)
      end

      defoverridable [
        start_link: 2,
        init: 1,
        terminate: 2,

        fetch: 4,
        save!: 3,
        save_async!: 3,
        reload!: 3,
        reload_async!: 3,
        ping!: 3,
        kill!: 3,
        crash!: 3,
        health_check!: 2,
        health_check!: 3,
        health_check!: 4,
      ]

    end # end quote
  end #end __using__
end
