#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
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

  @callback fetch!(any, any, any, any) :: any
  @callback save!(any, any, any) :: any
  @callback save_async!(any, any, any) :: any
  @callback load!(any, any, any) :: any
  @callback load_async!(any, any, any) :: any
  @callback reload!(any, any, any) :: any
  @callback reload_async!(any, any, any) :: any
  @callback ping(any, any, any) :: any
  @callback kill!(any, any, any) :: any
  @callback crash!(any, any, any) :: any
  @callback health_check!(any, any) :: any
  @callback health_check!(any, any, any) :: any
  @callback health_check!(any, any, any, any) :: any


  defmodule Default do
    alias Noizu.ElixirCore.OptionSettings
    alias Noizu.ElixirCore.OptionValue
    alias Noizu.ElixirCore.OptionList
    alias Noizu.SimplePool.V2.Server.State
    require Logger

    # @todo alternative solution for specifying features.
    @features ([:auto_load, :auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection])
    @default_features ([:auto_load, :lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection])

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



    defp get_semaphore(key, count \\ 1) do
      try do
        Semaphore.acquire(key, count)
      rescue _e -> false
      catch _e -> false
      end
    end

    def enable_server!(mod, active_key, elixir_node \\ nil) do
      cond do
        elixir_node == nil || elixir_node == node() ->
          if get_semaphore({:fg_write_record, active_key} , 5) do
            r = FastGlobal.put(active_key, true)
            Semaphore.release({:fg_write_record, active_key})
            r
          else
            # Always write attempt retrieve lock merely to prevent an over write if possible.
            r = FastGlobal.put(active_key, true)
            spawn fn ->
              Process.sleep(750)
              if get_semaphore({:fg_write_record, active_key} , 5) do
                FastGlobal.put(active_key, true)
                Semaphore.release({:fg_write_record, active_key})
              else
                FastGlobal.put(active_key, true)
              end
            end
            r
          end
        true -> :rpc.call(elixir_node, mod, :enable_server!, [])
      end
    end

    def server_online?(mod, active_key, elixir_node \\ nil) do
      cond do
        elixir_node == nil || elixir_node == node() ->
          case FastGlobal.get(active_key, :no_match) do
            :no_match ->
              if get_semaphore({:fg_write_record, active_key} , 1) do
                # Race condition check
                r = case FastGlobal.get(active_key, :no_match) do
                  :no_match ->
                    FastGlobal.put(active_key, false)
                  v -> v
                end
                Semaphore.release({:fg_write_record, active_key})
                r
              else
                false
              end
            v -> v
          end
        true -> :rpc.call(elixir_node, mod, :server_online?, [])
      end
    end

    def disable_server!(mod, active_key, elixir_node \\ nil) do
      cond do
        elixir_node == nil || elixir_node == node() ->
          if get_semaphore({:fg_write_record, active_key} , 5) do
            r = FastGlobal.put(active_key, false)
            Semaphore.release({:fg_write_record, active_key})
            r
          else
            # Always write attempt retrieve lock merely to prevent an over write if possible.
            r = FastGlobal.put(active_key, true)
            spawn fn ->
              Process.sleep(750)
              if get_semaphore({:fg_write_record, active_key} , 5) do
                FastGlobal.put(active_key, true)
                Semaphore.release({:fg_write_record, active_key})
              else
                FastGlobal.put(active_key, true)
              end
            end
            r
          end
        true -> :rpc.call(elixir_node, mod, :disable_server!, [])
      end
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

      _default_definition = case options.default_definition do
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
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.ServerBehaviour.Default)
    option_settings = implementation.prepare_options(options)

    # Temporary Hardcoding
    router_provider = Noizu.SimplePool.V2.RouterBehaviour.DefaultProvider
    worker_management_provider = Noizu.SimplePool.V2.WorkerManagementBehaviour.DefaultProvider
    service_management_provider = Noizu.SimplePool.V2.ServiceManagementBehaviour.DefaultProvider
    message_processing_provider = Noizu.SimplePool.V2.MessageProcessingBehaviour.DefaultProvider
    quote do
      # todo option value
      @timeout 30_000
      @implementation unquote(implementation)
      @option_settings :override

      @behaviour Noizu.SimplePool.V2.ServerBehaviour

      alias Noizu.SimplePool.Worker.Link
      alias Noizu.SimplePool.Server.EnvironmentDetails
      alias Noizu.SimplePool.V2.Server.State

      require Logger

      #----------------------------------------------------------
      #
      #----------------------------------------------------------
      use GenServer
      use Noizu.SimplePool.V2.SettingsBehaviour.Inherited, unquote([option_settings: option_settings])
      use unquote(message_processing_provider), unquote(option_settings)

      @active_key Module.concat(Enabled, __MODULE__)

      #----------------------------------------------------------
      # @todo We should be passing in information (pool module, instead of making this a sub module.)
      # @We may than provide some helper methods that append the extra data.
      #----------------------------------------------------------
      defmodule Router do
        use unquote(router_provider), unquote(option_settings)
      end

      #----------------------------------------------------------
      #
      #----------------------------------------------------------
      defmodule WorkerManagement do
        use unquote(worker_management_provider), unquote(option_settings)
      end

      #----------------------------------------------------------
      #
      #----------------------------------------------------------
      defmodule ServiceManagement do
        use unquote(service_management_provider), unquote(option_settings)
      end
      #----------------------------------------------------------

      def load_pool(context, options \\ %{}) do
        __MODULE__.ServiceManagement.load_pool(context, options)
      end

      # @deprecated
      def service_health_check!(%Noizu.ElixirCore.CallingContext{} = context), do: __MODULE__.ServiceManagement.service_health_check!(context)
      def service_health_check!(health_check_options, %Noizu.ElixirCore.CallingContext{} = context), do: __MODULE__.ServiceManagement.service_health_check!(health_check_options, context)
      def service_health_check!(health_check_options, %Noizu.ElixirCore.CallingContext{} = context, options), do: __MODULE__.ServiceManagement.service_health_check!(health_check_options, context, options)

      #==========================================================
      #
      #==========================================================
      def router(), do: __MODULE__.Router
      def worker_management(), do: __MODULE__.WorkerManagement
      def service_management(), do: __MODULE__.ServiceManagement

      @doc """
      Initialize meta data for this pool. (override default provided by SettingsBehaviour)
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
        args = %{definition: final_definition, context: context}
        GenServer.start_link(__MODULE__, args, name: __MODULE__, restart: :permanent)
      end

      #---------------
      # init
      #---------------
      def init(%{context: context, definition: definition} = args) do
        verbose() && Logger.info(fn -> {banner("INIT #{__MODULE__} (#{inspect pool_server()}@#{inspect self()})\n args: #{inspect args, pretty: true}"), Noizu.ElixirCore.CallingContext.metadata(context) } end)

        # @TODO we can avoid this jump by directly delegating to server_provider() and updating server_provider to fetch option_settings on its own.
        #server.enable_server!(node())
        #module.server_provider().init(module, :deprecated, definition, context, module.option_settings())

        state = initial_state(definition, context)

        __MODULE__.ServiceManagement.record_service_event!(:start, %{definition: definition, options: @option_settings}, context, %{})
        __MODULE__.enable_server!()
        {:ok, state}
      end

      def initial_state(definition, context) do
        #options = module.option_settings()
        # @TODO load real effective
        # @TODO V2 health check and monitors are different these structures need to be updated.

        #effective = %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{
        #  identifier: {node(), pool()},
        #  time_stamp: DateTime.utc_now(),
        #  status: :online,
        #  directive: :init,
        #  definition: args.definition,
        #}

        %State{
          pool: pool(),
          worker_supervisor: :deprecated,
          service: pool_server(), # deprecated

          status_details: :pending,
          extended: %{load_process: nil},
          #environment_details: %EnvironmentDetails{definition: definition, effective: effective, status: :init},
          environment_details: %{},
          options: @option_settings
        }
      end


      def terminate(reason, state) do
        context = nil
        __MODULE__.ServiceManagement.record_service_event!(:terminate, %{reason: reason}, context, @option_settings)
        Logger.warn( fn -> banner("Terminate #{inspect state, pretty: true}\nReason: #{inspect reason}") end)
        #this.server.disable_server!(node())
        :ok
      end



      #==========================================================
      # Built in Worker Convenience Methods.
      #==========================================================
      @doc """
      Request information about a worker.
      """
      def fetch!(ref, request \\ :state, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        case __MODULE__.Router.s_call!(ref, {:fetch!, {request}, options}, context, options) do
          {:nack, :no_registered_host} -> nil
          v -> v
        end
      end

      @doc """
      Bring worker online
      """
      def wake!(ref, request \\ :state, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call!(ref, {:wake!, {request}, options}, context, options)
      end

      @doc """
      Tell a worker to save its state.
      """
      def save!(ref, args \\ {}, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call!(ref, {:save!, args, options}, context, options)
      end

      @doc """
      Tell a worker to save its state, do not wait for response.
      """
      def save_async!(ref, args \\ {}, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast!(ref, {:save!, args, options}, context, options)
      end

      @doc """
      Tell a worker to reload its state.
      """
      def reload!(ref, args \\ {}, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call!(ref, {:reload!, args, options}, context, options)
      end

      @doc """
      Tell a worker to reload its state, do not wait for a response.
      """
      def reload_async!(ref, args \\ {}, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast!(ref, {:reload!, args, options}, context, options)
      end

      @doc """
      Start a new worker
      """
      def load!(ref, args \\ {}, context \\ nil, options \\ %{}) do
        context = Noizu.ElixirCore.CallingContext.system(context)
        __MODULE__.Router.s_call!(ref, {:load!, args, options}, context, options)
      end

      @doc """
      Start a new worker (async)
      """
      def load_async!(ref, args \\ {}, context \\ nil, options \\ %{}) do
        context = Noizu.ElixirCore.CallingContext.system(context)
        __MODULE__.Router.s_cast!(ref, {:load!, args, options}, context, options)
      end

      @doc """
      Ping worker.
      """
      def ping(ref, args \\ {}, context \\ nil, options \\ %{}) do
        timeout = options[:timeout] || @timeout
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call(ref, {:ping, args, options}, context, options, timeout)
      end

      @doc """
      Ping worker.
      """
      def ping!(ref, args \\ {}, context \\ nil, options \\ %{}) do
        timeout = options[:timeout] || @timeout
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call!(ref, {:ping, args, options}, context, options, timeout)
      end

      @doc """
      Send worker a kill request.
      """
      def kill!(ref, args \\ {}, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast(ref, {:kill!, args, options}, context, options)
      end

      @doc """
      Send a worker a crash (throw error) request.
      """
      def crash!(ref, args \\ {}, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast(ref, {:crash!, args, options}, context, options)
      end

      @doc """
      Request a health report from worker.
      """
      def health_check!(ref, args \\ {}, context \\ nil, options \\ %{}) do
        __MODULE__.Router.s_call!(ref, {:health_check!, args, options}, context, options)
      end

      #-----------------------------------------------------------------------------------------------------------------
      #
      #-----------------------------------------------------------------------------------------------------------------

      def worker_sup_start(ref, context) do
        Logger.warn("[V2] Server.worker_sup_start is deprecated")
        __MODULE__.WorkerManagement.worker_start(ref, context)
      end

      def lock!(context, o) do
        Logger.warn("[V2] Server.lock! is deprecated")
        __MODULE__.WorkerManagement.lock!(context, o)
      end

      def release!(context, o) do
        Logger.warn("[V2] Server.release! is deprecated")
        __MODULE__.WorkerManagement.release!(context, o)
      end


      #-----------------------------------------------------------------------------------------------------------------
      # Internal Call Handlers
      #-----------------------------------------------------------------------------------------------------------------
      def handle_status(state, _args, _from, _context, _options \\ nil) do
        {:reply, %{status: state.status_details, environment: state.environment_details}, state}
      end

      def handle_server_kill!(state, _args, _from, context, _options \\ nil) do
        {:stop, {:user_requested, context}, state}
      end

      def handle_release!(state, _args, _from, _context, _options \\ nil) do
        state = state
                |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:directive)], :active)
                |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], :online)
        {:reply, {:ack, state.environment_details.effective}, state}
      end

      def handle_lock!(state, _args, _from, _context, _options \\ nil) do
        state = state
                |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:directive)], :maintenance)
                |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], :locked)
        {:reply, {:ack, state.environment_details.effective}, state}
      end

      def handle_health_check!(state, _args, _from, _context, _options \\ nil) do
        dummy_response = %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{
          identifier: {node(), pool()},
          process: self(),
          time_stamp: DateTime.utc_now(),
          status: :online,
          directive: :free,
          definition: %Noizu.SimplePool.MonitoringFramework.Service.Definition{

            identifier: {node(), pool()},
            server: node(),
            pool: pool(),
            service: pool_server(),
            supervisor: pool_supervisor(),
            server_options: %{},
            worker_sup_options: %{},
            time_stamp: nil,
            hard_limit: 50,
            soft_limit: 50,
            target: 50,

          },
          allocated: %{},
          health_index: 5.0,
          events: [],
        }

        {:reply, dummy_response, state}
      end

      def handle_load_pool(state, args, from, context, options \\ nil) do
        state = if async_load() do
          load_pool_workers_async(state, args, from, context, options)
        else
          load_pool_workers(state, args, from, context, options)
        end
        {:reply, :ok, state}
      end

      def handle_load_complete(state, {process}, from, context, options \\ nil) do
        state = __MODULE__.ServiceManagement.load_complete(state, process, context)
        {:noreply, state}
      end

      #-----------------------------------------------------------------------------------------------------------------
      # Internal Scaffolding
      #-----------------------------------------------------------------------------------------------------------------

      def load_pool_workers(state, _args, _from, context, _options) do
        __MODULE__.ServiceManagement.load_complete(state, self(), context)
      end

      def load_pool_workers_async(state, args, from, context, options) do
        process = spawn fn ->
          load_pool_workers(state, args, from, context, options)
          __MODULE__.Router.internal_cast({:load_complete, self()}, context)
        end
        __MODULE__.ServiceManagement.load_begin(state, process, context)
      end


      #------------------------------------------------------------------------
      # Runtime Setting Getters
      #------------------------------------------------------------------------

      @doc """
      Auto load setting for pool.
      """
      def auto_load(), do: meta()[:auto_load]

      @doc """
      Auto load setting for pool.
      """
      def async_load(), do: meta()[:async_load]

      #------------------------------------------------------------------------
      # Infrastructure provided call router
      #------------------------------------------------------------------------
      def call_router_internal__default({:passive, envelope}, from, state), do: call_router_internal__default(envelope, from, state)
      def call_router_internal__default({:spawn, envelope}, from, state), do: call_router_internal__default(envelope, from, state)
      def call_router_internal__default(envelope, from, state) do
        case envelope do
          {:i, {:status, args}, context} -> handle_status(state, args, from, context)
          {:i, {:status, args, options}, context} -> handle_status(state, args, from, context, options)

          {:m, {:load_pool, args}, context} -> handle_load_pool(state, args, from, context)
          {:m, {:load_pool, args, opts}, context} -> handle_load_pool(state, args, from, context, opts)

          {:m, {:release!, args}, context} -> handle_release!(state, args, from, context)
          {:m, {:release!, args, opts}, context} -> handle_release!(state, args, from, context, opts)

          {:m, {:lock!, args}, context} -> handle_lock!(state, args, from, context)
          {:m, {:lock!, args, opts}, context} -> handle_lock!(state, args, from, context, opts)

          {:m, {:health_check!, args}, context} -> handle_health_check!(state, args, from, context)
          {:m, {:health_check!, args, opts}, context} -> handle_health_check!(state, args, from, context, opts)
          _ -> nil
        end
      end
      def call_router_internal(envelope, from, state), do: call_router_internal__default(envelope, from, state)


      #----------------------------
      #
      #----------------------------
      def cast_router_internal__default({:passive, envelope}, state), do: cast_router_internal__default(envelope, state)
      def cast_router_internal__default({:spawn, envelope}, state), do: cast_router_internal__default(envelope, state)
      def cast_router_internal__default(envelope, state) do
        r = case envelope do
          {:i, {:server_kill!, args}, context} -> handle_server_kill!(state, args, :cast, context)
          {:i, {:server_kill!, args, options}, context} -> handle_server_kill!(state, args, :cast, context, options)
          {:m, {:load_complete, args}, context} -> handle_load_complete(state, args, :cast, context)
          {:m, {:load_complete, args, opts}, context} -> handle_load_complete(state, args, :cast, context, opts)
          _ ->
            call_router_internal(envelope, :cast, state)
        end
        r && as_cast(r)
      end
      def cast_router_internal(envelope, state), do: cast_router_internal__default(envelope, state)

      #----------------------------
      #
      #----------------------------
      def count_supervisor_children(), do: worker_management().count_supervisor_children()

      def enable_server!(elixir_node \\ nil) do
        Noizu.SimplePool.V2.ServerBehaviour.Default.enable_server!(__MODULE__, @active_key, elixir_node)
      end

      def server_online?(elixir_node \\ nil) do
        Noizu.SimplePool.V2.ServerBehaviour.Default.server_online?(__MODULE__, @active_key, elixir_node)
      end

      def disable_server!(elixir_node \\ nil) do
        Noizu.SimplePool.V2.ServerBehaviour.Default.disable_server!(__MODULE__, @active_key, elixir_node)
      end


      defoverridable [
        start_link: 2,
        init: 1,
        initial_state: 2,
        terminate: 2,

        load_pool: 2,
        load_pool_workers: 5,
        load_pool_workers_async: 5,

        handle_status: 5,
        handle_server_kill!: 5,
        handle_load_pool: 5,
        handle_load_complete: 5,
        handle_release!: 5,
        handle_lock!: 5,
        handle_health_check!: 5,
        call_router_internal: 3,
        cast_router_internal: 2,

        fetch!: 4,
        wake!: 4,
        save!: 4,
        save_async!: 4,
        reload!: 4,
        reload_async!: 4,
        load!: 4,
        load_async!: 4,
        ping: 4,
        ping!: 4,
        kill!: 4,
        crash!: 4,
        health_check!: 4,

        enable_server!: 1,
        server_online?: 1,
        disable_server!: 1
      ]

    end # end quote
  end #end __using__
end
