#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Server.DefaultImplementation do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList
  require Logger
  # @TODO - @PRI1 - Make this a behavior, delegate router, supervisor and server provider calls based off of input.

  @callback option_settings() :: Map.t
  @callback start_link(any, any, any) :: any

  @methods ([
              :accept_transfer!, :verbose, :worker_state_entity, :option_settings, :options, :start_link, :init,
              :terminate, :enable_server!, :disable_server!, :worker_sup_start,
              :worker_sup_terminate, :worker_sup_remove, :worker_lookup_handler, :base, :pool_supervisor,
              :status, :load, :load_complete, :ref, :worker_add!, :run_on_host,
              :cast_to_host, :remove!, :r_remove!, :terminate!, :r_terminate!,
              :workers!, :worker_migrate!, :worker_load!, :worker_ref!,
              :worker_pid!, :self_call, :self_cast, :internal_call, :internal_cast,  :internal_system_call, :internal_system_cast,
              :remote_system_call, :remote_system_cast, :remote_call, :remote_cast, :fetch, :save!, :reload!, :ping!, :server_kill!, :kill!, :crash!,
              :service_health_check!, :health_check!, :get_direct_link!, :s_call_unsafe, :s_cast_unsafe, :rs_call!,
              :s_call!, :rs_cast!, :s_cast!, :rs_call, :s_call, :rs_cast, :s_cast,
              :link_forward!, :record_service_event!, :lock!, :release!, :status_wait, :entity_status,
              :bulk_migrate!, :o_call, :o_cast,
              :active_supervisors, :supervisor_by_index, :available_supervisors, :current_supervisor, :count_supervisor_children, :group_supervisor_children,
              :catch_all
            ])
  @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection])
  @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection])

  @default_timeout 15_000
  @default_shutdown_timeout 30_000

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{

        implementation: %OptionValue{option: :implementation, default: Application.get_env(:noizu_simple_pool, :default_server_provider, Noizu.SimplePool.V2.Server.DefaultImplementation)},
        supervisor_implementation: %OptionValue{option: :supervisor_implementation, default: Application.get_env(:noizu_simple_pool, :default_supervisor_provider, Noizu.SimplePool.V2.Server.Supervisor.DefaultImplementation)},
        route_implementation: %OptionValue{option: :route_implementation, default: Application.get_env(:noizu_simple_pool, :default_route_provider, Noizu.SimplePool.V2.Server.Router.DefaultImplementation)},
        server_provider: %OptionValue{option: :server_provider, default: Application.get_env(:noizu_simple_pool, :default_server_provider, Noizu.SimplePool.V2.Server.WorkerManagement.DefaultImplementation)},

        features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: :auto},
        worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
        default_timeout: %OptionValue{option: :default_timeout, default:  Application.get_env(:noizu_simple_pool, :default_timeout, @default_timeout)},
        shutdown_timeout: %OptionValue{option: :shutdown_timeout, default: Application.get_env(:noizu_simple_pool, :default_shutdown_timeout, @default_shutdown_timeout)},
        default_definition: %OptionValue{option: :default_definition, default: :auto},
        server_driver: %OptionValue{option: :server_driver, default: Application.get_env(:noizu_simple_pool, :default_server_driver, Noizu.SimplePool.ServerDriver.Default)},
        worker_lookup_handler: %OptionValue{option: :worker_lookup_handler, default: Application.get_env(:noizu_simple_pool, :worker_lookup_handler, Noizu.SimplePool.WorkerLookupBehaviour.Default)},

        server_monitor:   %OptionValue{option: :server_monitor, default:  Application.get_env(:noizu_simple_pool, :default_server_monitr, Noizu.SimplePool.MonitoringFramework.MonitorBehaviour.Default)},
        log_timeouts: %OptionValue{option: :log_timeouts, default: Application.get_env(:noizu_simple_pool, :default_log_timeouts, true)},
        max_supervisors: %OptionValue{option: :max_supervisors, default: Application.get_env(:noizu_simple_pool, :default_max_supervisors, 100)},
      }
    }

    initial = OptionSettings.expand(settings, options)
    modifications = Map.put(initial.effective_options, :required, List.foldl(@methods, %{}, fn(x, acc) -> Map.put(acc, x, initial.effective_options.only[x] && !initial.effective_options.override[x]) end))
    %OptionSettings{initial| effective_options: Map.merge(initial.effective_options, modifications)}
  end

  #---------------
  # Meta
  #---------------
  defdelegate meta(module), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  defdelegate meta(module, update), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  def meta_init(module) do
    options = module.options()
    %{
      verbose: meta_init_verbose(module, options),
      default_definition: meta_init_default_definition(module, options),
    }
  end

  def meta_init_verbose(module, options) do
    options.verbose == :auto && module.pool().verbose() || options.verbose
  end

  def meta_init_default_definition(module, options) do
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


  #=========================================================================
  # Genserver Lifecycle & Releated
  #=========================================================================

  #---------------
  # start_link
  #---------------
  def start_link(module, sup, definition, context) do
    final_definition = definition == :default && module.default_definition() || definition
    if module.verbose() do
      Logger.info(fn ->
        default_snippet = (definition == :default) && " (:default)" || ""
        {module.banner("START_LINK #{module} (#{inspect module.worker_supervisor()}@#{inspect self()})\ndefinition#{default_snippet}: #{inspect final_definition}"), Noizu.ElixirCore.CallingContext.metadata(context)}
      end)
    end
    GenServer.start_link(module, [:deprecated, final_definition, context], name: module, restart: :permanent)
  end

  #---------------
  # init
  #---------------
  def init(module, [_sup, definition, context] = args) do
    if module.verbose() do
      Logger.info(fn -> {module.banner("INIT #{module} (#{inspect module.worker_supervisor()}@#{inspect self()})\n args: #{inspect args, pretty: true}"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
    end
    # @TODO we can avoid this jump by directly delegating to server_provider() and updating server_prover to fetch option_settings on its own.
    module.server_provider().init(module, :deprecated, definition, context, module.option_settings())
  end

  def terminate(module, reason, state) do
    module.server_provider().terminate(module, reason, state, nil, %{})
  end

  def enable_server!(module, elixir_node) do
    #@TODO reimplement pri1
    #@server_monitor.enable_server!(module.pool, elixir_node)
    :pending
  end

  def disable_server!(module, elixir_node) do
    #@TODO reimplement pri1
    #@server_monitor.disable_server!(module.pool, elixir_node)
    :pending
  end

  def accept_transfer!(module, ref, state, context , options), do: throw "PRI0"
  def lock!(module, context, options), do: throw "PRI0"
  def release!(module, context, options), do: throw "PRI0"
  def status_wait(module, target_state, context, timeout), do: throw "PRI0"
  def entity_status(module, context, options), do: throw "PRI0"

  def fetch(module, identifier, fetch_options, context , options), do: throw "PRI0"
  def save!(module, identifier, context , options), do: throw "PRI0"
  def save_async!(module, identifier, context), do: throw "PRI0"
  def reload!(module, identifier, context , options), do: throw "PRI0"
  def reload_async!(module, identifier, context , options), do: throw "PRI0"
  def ping!(module, identifier, context , options), do: throw "PRI0"
  def kill!(module, identifier, context , options), do: throw "PRI0"
  def server_kill!(module, context , options), do: throw "PRI0"
  def crash!(module, identifier, context , options), do: throw "PRI0"
  def service_health_check!(module, health_check_options, context, options), do: throw "PRI0"
  def health_check!(module, identifier, health_check_options, context, options), do: throw "PRI0"
  def record_service_event!(module, event, details, context, options), do: throw "PRI0"

  #---------------
  # default_definition
  #---------------
  def default_definition(module) do
    default = module.meta()[:default_definition]
    put_in(default, [Access.key(:time_stamp)], DateTime.utc_now())
  end
end