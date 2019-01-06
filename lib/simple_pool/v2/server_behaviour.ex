#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.ServerBehaviour do
  require Logger
  @callback pool() :: module
  @callback pool_worker_supervisor() :: module
  @callback pool_server() :: module
  @callback pool_supervisor() :: module
  @callback pool_worker() :: module
  @callback banner(String.t) :: String.t
  @callback banner(String.t, String.t) :: String.t
  @callback meta() :: Map.t
  @callback meta(Map.t) :: Map.t
  @callback meta_init() :: Map.t
  @callback options() :: Map.t
  @callback option_settings() :: Map.t

  #=================================================================
  #=================================================================
  # @__using__
  #=================================================================
  #=================================================================
  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.Server.DefaultImplementation)
    option_settings = implementation.prepare_options(options)
    options = option_settings.effective_options
    implementation = options.implementation
    worker_lookup_handler = options.worker_lookup_handler
    default_timeout = options.default_timeout
    max_supervisors = options.max_supervisors
    shutdown_timeout = options.shutdown_timeout
    server_monitor = options.server_monitor
    route_implementation = options.route_implementation
    server_provider = options.server_provider
    features = MapSet.new(options.features)
    supervisor_implementation = options.supervisor_implementation

    case Map.keys(option_settings.output.errors) do
      [] -> :ok
      l when is_list(l) ->
        Logger.error "
    ---------------------- Errors In Pool Settings  ----------------------------
    #{inspect option_settings, pretty: true, limit: :infinity}
    ----------------------------------------------------------------------------
        "
    end

    #features = MapSet.new(options.features)
    quote do
      @behaviour Noizu.SimplePool.V2.ServerBehaviour
      alias Noizu.SimplePool.Worker.Link
      use GenServer
      require Logger

      # Review for Deprecation
      @server_provider (unquote(server_provider))
      @worker_management_implementation @server_provider
      @worker_lookup_handler (unquote(worker_lookup_handler))
      @module_and_lookup_handler ({__MODULE__, @worker_lookup_handler})
      @server_monitor unquote(server_monitor)

      #---------------------------
      # review above for removal.
      #---------------------------
      @timeout (unquote(default_timeout))

      @implementation unquote(implementation)
      @supervisor_implementation unquote(supervisor_implementation)

      @parent unquote(__MODULE__)
      @module __MODULE__
      @module_name "#{@module}"

      # Related Modules.
      @pool @implementation.pool(@module)

      @pool_worker_state_entity @implementation.pool_worker_state_entity(@pool, unquote(options.worker_state_entity))
      @worker_state_entity @pool_worker_state_entity

      @max_supervisors (unquote(max_supervisors))
      @worker_supervisor (Module.concat([@pool, "WorkerSupervisor_S1"]))
      @worker_supervisors Enum.map(1..@max_supervisors, fn(x) -> {x, Module.concat([@pool, "WorkerSupervisor_S#{x}"])} end) |> Map.new()
      @available_supervisors Map.values(@worker_supervisors)


      @meta_key Module.concat(@module, "Meta")

      @options unquote(Macro.escape(options))
      @option_settings unquote(Macro.escape(option_settings))

      @shutdown_timeout (unquote(shutdown_timeout))
      @graceful_stop unquote(MapSet.member?(features, :graceful_stop))

      #@strategy unquote(strategy)
      #@restart_type unquote(restart_type)
      #@max_seconds unquote(max_seconds)
      #@max_restarts unquote(max_restarts)

      # @WIP - selection logic.
      @route_implementation unquote(route_implementation)
      @link_implementation Noizu.SimplePool.V2.Server.Router.RedirectProvider

      # @TODO required?
      @default_definition @options.default_definition

      #-------------------
      #
      #-------------------
      def banner(msg), do: banner(@module_name, msg)
      defdelegate banner(header, msg), to: @pool

      #-------------------
      #
      #-------------------
      def verbose(), do: meta()[:verbose]

      #-------------------
      #
      #-------------------
      # deprecated
      def server_provider(), do: @worker_management_implementation

      def worker_management_implementation(), do: @worker_management_implementation

      #-------------------
      #
      #-------------------
      def meta_key(), do: @meta_key

      #-------------------
      #
      #-------------------
      def meta(), do: _imp_meta(@module)
      defdelegate _imp_meta(module), to: @implementation, as: :meta

      #-------------------
      #
      #-------------------
      def meta(update), do: _imp_meta(@module, update)
      defdelegate _imp_meta(module, update), to: @implementation, as: :meta

      #-------------------
      #
      #-------------------
      def meta_init(), do: _imp_meta_init(@module)
      defdelegate _imp_meta_init(module), to: @implementation, as: :meta_init

      #-------------------
      #
      #-------------------
      def option_settings(), do: @option_settings

      #-------------------
      #
      #-------------------
      def options(), do: @options

      #-------------------
      #
      #-------------------
      defdelegate pool(), to: @pool

      #-------------------
      #
      #-------------------
      defdelegate pool_worker_supervisor(), to: @pool

      #-------------------
      #
      #-------------------
      defdelegate pool_server(), to: @pool

      #-------------------
      #
      #-------------------
      defdelegate pool_supervisor(), to: @pool

      #-------------------
      #
      #-------------------
      defdelegate pool_worker(), to: @pool


      @doc """
      Pool's worker state entity.
      """
      defdelegate pool_worker_state_entity(), to: @pool

      #-------------------
      #
      #-------------------
      defdelegate worker_state_entity(), to: @pool, as: :pool_worker_state_entity

      #=========================================================================
      # Supervisor Strategy
      #=========================================================================
      def superviser_meta() do
        # @TODO - use fast global, store data in one place so it matches what is spawned my pool superviser strategy (e.g. defdelegate).
        %{
          active_supervisors: @max_supervisors,
          available_supervisors: @available_supervisors,
          worker_supervisors: @worker_supervisors,
    #      default_supervisor: @worker_supervisor,
          graceful_stop: @graceful_stop,
          shutdown_timeout: @shutdown_timeout
        }

      end

      #-----------
      # count_supervisor_children
      #-----------
      def count_supervisor_children(), do: _imp_count_supervisor_children(@module)
      defdelegate _imp_count_supervisor_children(module), to: @supervisor_implementation, as: :count_supervisor_children

      #-----------
      # group_supervisor_children
      #-----------
      def group_supervisor_children(group_fun), do: _imp_group_supervisor_children(@module, group_fun)
      defdelegate _imp_group_supervisor_children(module, group_fun), to: @supervisor_implementation, as: :group_supervisor_children

      #-----------
      # active_supervisors
      #-----------
      def active_supervisors(), do: _imp_active_supervisors(@module)
      defdelegate _imp_active_supervisors(module), to: @supervisor_implementation, as: :active_supervisors

      #-----------
      # worker_supervisors
      #-----------
      def worker_supervisors(), do: _imp_worker_supervisors(@module)
      defdelegate _imp_worker_supervisors(module), to: @supervisor_implementation, as: :worker_supervisors

      #-----------
      # supervisor_by_index
      #-----------
      def supervisor_by_index(index), do: _imp_supervisor_by_index(@module, index)
      defdelegate _imp_supervisor_by_index(module, index), to: @supervisor_implementation, as: :supervisor_by_index

      #-----------
      # available_supervisors
      #-----------
      def available_supervisors(), do: _imp_available_supervisors(@module)
      defdelegate _imp_available_supervisors(module), to: @supervisor_implementation, as: :available_supervisors

      #-----------
      # supervisor_current_supervisor
      #-----------
      def supervisor_current_supervisor(ref), do: _imp_current_supervisor(@module, ref)
      defdelegate _imp_current_supervisor(module, ref), to: @supervisor_implementation, as: :current_supervisor

      #=========================================================================
      # Genserver Lifecycle & Releated
      #=========================================================================

      #-----------
      # start_link
      #-----------
      def start_link(sup, definition, context), do: _imp_start_link(@module, sup, definition, context)
      defdelegate _imp_start_link(module, sup, definition, context), to: @implementation, as: :start_link

      #-----------
      # init
      #-----------
      def init(args), do: _imp_init(@module, args)
      defdelegate _imp_init(module, args), to: @implementation, as: :init

      #-----------
      # terminate
      #-----------
      def terminate(reason, state), do: _imp_terminate(@module, reason, state)
      defdelegate _imp_terminate(module, reason, state), to: @implementation, as: :terminate

      #-----------
      # default_definition
      #-----------
      def default_definition(), do: _imp_default_definition(@module)
      defdelegate _imp_default_definition(module), to: @implementation, as: :default_definition

      #-----------
      # enable_server!
      #-----------
      def enable_server!(elixir_node), do: _imp_enable_server!(@module, elixir_node)
      defdelegate _imp_enable_server!(module, elixir_node), to: @implementation, as: :enable_server!

      #-----------
      #
      #-----------
      def disable_server!(elixir_node), do: _imp_disable_server!(@module, elixir_node)
      defdelegate _imp_disable_server!(module, elixir_node), to: @implementation, as: :disable_server!

      #-----------
      #
      #-----------
      def worker_sup_start(ref, transfer_state, context), do: _imp_worker_sup_start(@module, ref, transfer_state, context)
      defdelegate _imp_worker_sup_start(module, ref, transfer_state, context), to: @supervisor_implementation, as: :worker_sup_start

      def worker_sup_start(ref, context), do: _imp_worker_sup_start(@module, ref, context)
      defdelegate _imp_worker_sup_start(module, ref, context), to: @supervisor_implementation, as: :worker_sup_start

      def worker_sup_terminate(ref, sup, context, options \\ %{}), do: _imp_worker_sup_terminate(@module, ref, sup, context, options)
      defdelegate _imp_worker_sup_terminate(module, ref, sup, context, options), to: @supervisor_implementation, as: :worker_sup_terminate

      def worker_sup_remove(ref, sup, context, options \\ %{}), do: _imp_worker_sup_remove(@module, ref, sup, context, options)
      defdelegate _imp_worker_sup_remove(module, ref, sup, context, options), to: @supervisor_implementation, as: :worker_sup_remove

      def worker_lookup_handler(), do: @worker_lookup_handler

      def base(), do: pool()

      #-------------------------------------------------------------------------------
      # Startup: Lazy Loading/Async Load/Immediate Load strategies. Blocking/Lazy Initialization, Loading Strategy.
      #-------------------------------------------------------------------------------
      def status(context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: status(@module, context)
      defdelegate status(module, context), to: @worker_management_implementation

      def load(context \\ Noizu.ElixirCore.CallingContext.system(%{}), settings \\ %{}), do: load(@module, context, settings)
      defdelegate load(module, context, settings), to: @worker_management_implementation

      defdelegate load_complete(this, process, context), to: @worker_management_implementation

      defdelegate id(ref), to: @worker_state_entity
      defdelegate ref(ref), to: @worker_state_entity
      defdelegate entity(ref, options \\ %{}), to: @worker_state_entity
      defdelegate entity!(ref, options \\ %{}), to: @worker_state_entity
      defdelegate record(ref, options \\ %{}), to: @worker_state_entity
      defdelegate record!(ref, options \\ %{}), to: @worker_state_entity

      #-------------------------------------------------------------------------------
      # Worker Process Management
      #-------------------------------------------------------------------------------
      def worker_add!(ref, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_worker_add!(@module, ref, context, options)
      defdelegate _imp_worker_add!(module, ref, context, options), to: @supervisor_implementation, as: :worker_add!

      def run_on_host(ref, mfa, context, options \\ %{}, timeout \\ 30_000), do: _imp_run_on_host(@module, ref, mfa, context, options, timeout)
      defdelegate _imp_run_on_host(module, ref, mfa, context, options, timeout), to: @supervisor_implementation, as: :run_on_host

      def cast_to_host(ref, mfa, context, options \\ %{}, timeout \\ 30_000), do: _imp_cast_to_host(@module, ref, mfa, context, options, timeout)
      defdelegate _imp_cast_to_host(module, ref, mfa, context, options, timeout), to: @supervisor_implementation, as: :cast_to_host

      def remove!(ref, context, options), do: _imp_remove!(@module, ref, context, options)
      defdelegate _imp_remove!(module, ref, context, options), to: @supervisor_implementation, as: :remove!

      def terminate!(ref, context, options), do: _imp_terminate!(@module, ref, context, options)
      defdelegate _imp_terminate!(module, ref, context, options), to: @supervisor_implementation, as: :terminate!

      def bulk_migrate!(transfer_server, context, options), do: _imp_bulk_migrate!(@module, transfer_server, context, options)
      defdelegate _imp_bulk_migrate!(module, transfer_server, context, options), to: @supervisor_implementation, as: :bulk_migrate!

      def worker_migrate!(ref, rebase, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_worker_migrate!(@module, ref, rebase, context, options)
      defdelegate _imp_worker_migrate!(module, ref, rebase, context, options), to: @supervisor_implementation, as: :worker_migrate!

      def worker_load!(ref, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_worker_load!(@module, ref, context, options)
      defdelegate _imp_worker_load!(module, ref, context, options), to: @supervisor_implementation, as: :worker_load!

      def worker_ref!(identifier, _context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: _imp_worker_ref!(@module, identifier, _context )
      defdelegate _imp_worker_ref!(module, identifier, _context ), to: @supervisor_implementation, as: :worker_ref!

      def worker_pid!(ref, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_worker_pid!(@module, ref, context , options )
      defdelegate _imp_worker_pid!(module, ref, context , options ), to: @supervisor_implementation, as: :worker_pid!

      def accept_transfer!(ref, state, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_accept_transfer!(@module, ref, state, context , options )
      defdelegate _imp_accept_transfer!(module, ref, state, context , options ), to: @implementation, as: :accept_transfer!

      def lock!(context, options \\ %{}), do: _imp_lock!(@module, context, options)
      defdelegate _imp_lock!(module, context, options), to: @implementation, as: :lock!

      def release!(context, options \\ %{}), do: _imp_release!(@module, context, options )
      defdelegate _imp_release!(module, context, options ), to: @implementation, as: :release!

      def status_wait(target_state, context, timeout \\ :infinity), do: _imp_status_wait(@module, target_state, context, timeout)
      defdelegate _imp_status_wait(module, target_state, context, timeout), to: @implementation, as: :status_wait

      def entity_status(context, options \\ %{}), do: _imp_entity_status(@module, context, options )
      defdelegate _imp_entity_status(module, context, options ), to: @implementation, as: :entity_status

      def self_call(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_self_call(@module, call, context , options )
      defdelegate _imp_self_call(module, call, context , options ), to: @route_implementation, as: :self_call

      def self_cast(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_self_cast(@module, call, context , options )
      defdelegate _imp_self_cast(module, call, context , options ), to: @route_implementation, as: :self_cast

      def internal_system_call(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_internal_system_call(@module, call, context , options )
      defdelegate _imp_internal_system_call(module, call, context , options ), to: @route_implementation, as: :internal_system_call

      def internal_system_cast(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_internal_system_cast(@module, call, context , options )
      defdelegate _imp_internal_system_cast(module, call, context , options ), to: @route_implementation, as: :internal_system_cast

      def internal_call(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_internal_call(@module, call, context , options )
      defdelegate _imp_internal_call(module, call, context , options ), to: @route_implementation, as: :internal_call

      def internal_cast(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_internal_cast(@module, call, context , options )
      defdelegate _imp_internal_cast(module, call, context , options ), to: @route_implementation, as: :internal_cast

      def remote_system_call(remote_node, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_remote_system_call(@module, remote_node, call, context , options )
      defdelegate _imp_remote_system_call(module, remote_node, call, context , options ), to: @route_implementation, as: :remote_system_call

      def remote_system_cast(remote_node, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_remote_system_cast(@module, remote_node, call, context , options )
      defdelegate _imp_remote_system_cast(module, remote_node, call, context , options ), to: @route_implementation, as: :remote_system_cast

      def remote_call(remote_node, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_remote_call(@module, remote_node, call, context , options )
      defdelegate _imp_remote_call(module, remote_node, call, context , options ), to: @route_implementation, as: :remote_call

      def remote_cast(remote_node, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_remote_cast(@module, remote_node, call, context , options )
      defdelegate _imp_remote_cast(module, remote_node, call, context , options ), to: @route_implementation, as: :remote_cast

      def fetch(identifier, fetch_options \\ %{}, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_fetch(@module, identifier, fetch_options, context , options )
      defdelegate _imp_fetch(module, identifier, fetch_options, context , options ), to: @implementation, as: :fetch

      def save!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_save!(@module, identifier, context , options )
      defdelegate _imp_save!(module, identifier, context , options ), to: @implementation, as: :save!

      def save_async!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: _imp_save_async!(@module, identifier, context )
      defdelegate _imp_save_async!(module, identifier, context ), to: @implementation, as: :save_async!

      def reload!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_reload!(@module, identifier, context , options )
      defdelegate _imp_reload!(module, identifier, context , options ), to: @implementation, as: :reload!

      def reload_async!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_reload_async!(@module, identifier, context , options )
      defdelegate _imp_reload_async!(module, identifier, context , options ), to: @implementation, as: :reload_async!

      def ping!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_ping!(@module, identifier, context , options )
      defdelegate _imp_ping!(module, identifier, context , options ), to: @implementation, as: :ping!

      def kill!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_kill!(@module, identifier, context , options )
      defdelegate _imp_kill!(module, identifier, context , options ), to: @implementation, as: :kill!

      def server_kill!(context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_server_kill!(@module, context , options )
      defdelegate _imp_server_kill!(module, context , options ), to: @implementation, as: :server_kill!

      def crash!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_crash!(@module, identifier, context , options )
      defdelegate _imp_crash!(module, identifier, context , options ), to: @implementation, as: :crash!

      def service_health_check!(%Noizu.ElixirCore.CallingContext{} = context), do: _imp_service_health_check!(@module, %{}, context, %{})
      def service_health_check!(health_check_options, %Noizu.ElixirCore.CallingContext{} = context), do: _imp_service_health_check!(@module, health_check_options, context, %{})
      def service_health_check!(health_check_options, %Noizu.ElixirCore.CallingContext{} = context, options), do: _imp_service_health_check!(@module, health_check_options, context, options)
      defdelegate _imp_service_health_check!(module, health_check_options, context, options), to: @implementation, as: :service_health_check!

      def health_check!(identifier, %Noizu.ElixirCore.CallingContext{} = context), do: _imp_health_check!(@module, identifier, %{}, context, %{})
      def health_check!(identifier, health_check_options, %Noizu.ElixirCore.CallingContext{} = context), do: _imp_health_check!(@module, identifier, health_check_options, context, %{})
      def health_check!(identifier, health_check_options, %Noizu.ElixirCore.CallingContext{} = context, options), do: _imp_health_check!(@module, identifier, health_check_options, context, options)
      defdelegate _imp_health_check!(module, identifier, health_check_options, context, options), to: @implementation, as: :health_check!

      def get_direct_link!(ref, context, options \\ %{spawn: false}), do: _imp_get_direct_link!(@module, ref, context, options)
      defdelegate _imp_get_direct_link!(module, ref, context, options), to: @route_implementation, as: :get_direct_link!

      def s_call_unsafe(ref, extended_call, context, options \\ %{}, timeout \\ @timeout), do: _imp_s_call_unsafe(@module, ref, extended_call, context, options , timeout)
      defdelegate _imp_s_call_unsafe(module, ref, extended_call, context, options , timeout), to: @route_implementation, as: :s_call_unsafe

      def s_cast_unsafe(ref, extended_call, context, options \\ %{}), do: _imp_s_cast_unsafe(@module, ref, extended_call, context, options )
      defdelegate _imp_s_cast_unsafe(module, ref, extended_call, context, options ), to: @route_implementation, as: :s_cast_unsafe

      #===============================
      # call forwarding
      #===============================
      def handle_call(envelope, from, state), do: _imp_route_call(@module, envelope, from, state)
      defdelegate _imp_route_call(module, envelope, from, state), to: @route_implementation, as: :route_call

      def handle_cast(envelope, state), do: _imp_route_cast(@module, envelope, state)
      defdelegate _imp_route_cast(module, envelope, state), to: @route_implementation, as: :route_cast

      def handle_info(envelope, state), do: _imp_route_info(@module, envelope, state)
      defdelegate _imp_route_info(module, envelope, state), to: @route_implementation, as: :route_info

      def extended_call(ref, timeout, call, context), do: _imp_extended_call(@module, ref, timeout, call, context)
      defdelegate _imp_extended_call(module, ref, timeout, call, context), to: @route_implementation, as: :extended_call

      def s_call!(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(), options \\ %{}), do: _imp_s_call!(@module, identifier, call, context, options)
      defdelegate _imp_s_call!(module, identifier, call, context, options), to: @route_implementation, as: :s_call!

      def s_call(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(), options \\ %{}), do: _imp_s_call(@module, identifier, call, context, options)
      defdelegate _imp_s_call(module, identifier, call, context, options), to: @route_implementation, as: :s_call

      def s_cast!(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(), options \\ %{}), do: _imp_s_cast!(@module, identifier, call, context, options)
      defdelegate _imp_s_cast!(module, identifier, call, context, options), to: @route_implementation, as: :s_cast!

      def s_cast(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(), options \\ %{}), do: _imp_s_cast(@module, identifier, call, context, options)
      defdelegate _imp_s_cast(module, identifier, call, context, options), to: @route_implementation, as: :s_cast

      def workers!(server, %Noizu.ElixirCore.CallingContext{} = context), do: _imp_workers!(@module, server, context, %{})
      def workers!(server, %Noizu.ElixirCore.CallingContext{} = context, options), do: _imp_workers!(@module, server, context, options)
      def workers!(%Noizu.ElixirCore.CallingContext{} = context), do: _imp_workers!(@module, node(), context, %{})
      def workers!(%Noizu.ElixirCore.CallingContext{} = context, options), do: _imp_workers!(@module, node(), context, options)
      defdelegate _imp_workers!(module, server, context, options), to: @worker_lookup_handler, as: :workers!

      def link_forward!(%Link{handler: __MODULE__} = link, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: _imp_link_forward!(@module, link, call, context, options)
      defdelegate _imp_link_forward!(module, link, call, context, options), to: @route_implementation, as: :link_forward!

      def record_service_event!(event, details, context, options), do: _imp_record_service_event!(@module, event, details, context, options)
      defdelegate _imp_record_service_event!(module, event, details, context, options), to: @implementation, as: :record_service_event!

      # m ?? - review use cases for this call type. may be redundant to i_* handlers.
      def m_call_handler(call, context, from, state), do: m_call_handler(@module, call, context, from, state)
      defdelegate m_call_handler(module, call, context, from, state), to: @worker_management_implementation
      def m_cast_handler(call, context, state), do: m_cast_handler(@module, call, context, state)
      defdelegate m_cast_handler(module, call, context, state), to: @worker_management_implementation
      def m_info_handler(call, context, state), do: m_info_handler(@module, call, context, state)
      defdelegate m_info_handler(module, call, context, state), to: @worker_management_implementation

      # Worker Call (to worker process)
      def s_call_handler(call, context, from, state), do: m_call_handler(@module, call, context, from, state)
      defdelegate s_call_handler(module, call, context, from, state), to: @worker_management_implementation
      def s_cast_handler(call, context, state), do: m_cast_handler(@module, call, context, state)
      defdelegate s_cast_handler(module, call, context, state), to: @worker_management_implementation
      def s_info_handler(call, context, state), do: m_info_handler(@module, call, context, state)
      defdelegate s_info_handler(module, call, context, state), to: @worker_management_implementation

      # Internal Call (to server)
      def i_call_handler(call, context, from, state), do: m_call_handler(@module, call, context, from, state)
      defdelegate i_call_handler(module, call, context, from, state), to: @worker_management_implementation
      def i_cast_handler(call, context, state), do: m_cast_handler(@module, call, context, state)
      defdelegate i_cast_handler(module, call, context, state), to: @worker_management_implementation
      def i_info_handler(call, context, state), do: m_info_handler(@module, call, context, state)
      defdelegate i_info_handler(module, call, context, state), to: @worker_management_implementation

    end # end quote
  end #end __using__
end
