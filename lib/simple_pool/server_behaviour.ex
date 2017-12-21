#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.ServerBehaviour do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList
  alias Noizu.SimplePool.Worker.Link
  require Logger

  @callback option_settings() :: Map.t
  @callback start_link(any) :: any

  @methods ([
              :start_link, :init, :terminate!, :terminate, :load, :status, :worker_pid!, :worker_ref!, :worker_clear!,
              :worker_deregister!, :worker_register!, :worker_load!, :worker_migrate!, :worker_start_transfer!, :worker_remove!, :worker_terminate!,
              :worker_add!, :get_direct_link!, :link_forward!, :load_complete, :ref, :ping!, :kill!,
              :crash!, :health_check!, :save!, :reload!, :remove!
            ])
  @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection])
  @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection])

  @default_timeout 15_000
  @default_shutdown_timeout 30_000

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: :auto},
        worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
        default_timeout: %OptionValue{option: :default_timeout, default:  Application.get_env(:noizu_simple_pool, :default_timeout, @default_timeout)},
        shutdown_timeout: %OptionValue{option: :shutdown_timeout, default: Application.get_env(:noizu_simple_pool, :default_shutdown_timeout, @default_shutdown_timeout)},
        server_driver: %OptionValue{option: :server_driver, default: Application.get_env(:noizu_simple_pool, :default_server_driver, Noizu.SimplePool.ServerDriver.Default)},
        worker_lookup_handler: %OptionValue{option: :worker_lookup_handler, default: Application.get_env(:noizu_simple_pool, :worker_lookup_handler, Noizu.SimplePool.WorkerLookupBehaviour.Default)},
        server_provider: %OptionValue{option: :server_provider, default: Application.get_env(:noizu_simple_pool, :default_server_provider, Noizu.SimplePool.Server.ProviderBehaviour.Default)},
        server_monitor:   %OptionValue{option: :server_monitor, default:  Application.get_env(:noizu_simple_pool, :default_server_monitor, Noizu.SimplePool.ServerMonitorBehaviour.DefaultImplementation)},
      }
    }

    initial = OptionSettings.expand(settings, options)
    modifications = Map.put(initial.effective_options, :required, List.foldl(@methods, %{}, fn(x, acc) -> Map.put(acc, x, initial.effective_options.only[x] && !initial.effective_options.override[x]) end))
    %OptionSettings{initial| effective_options: Map.merge(initial.effective_options, modifications)}
  end

  def default_verbose(verbose, base) do
    if verbose == :auto do
      if Application.get_env(:noizu_simple_pool, base, %{})[:PoolSupervisor][:verbose] do
        Application.get_env(:noizu_simple_pool, base, %{})[:PoolSupervisor][:verbose]
      else
        Application.get_env(:noizu_simple_pool, :verbose, false)
      end
    else
      verbose
    end
  end

  def default_run_on_host(mod, worker_lookup_handler, ref, {m,f,a}, context, options \\ %{}, timeout \\ 30_000) do
    case worker_lookup_handler.host!(ref, mod, context, options) do
      {:ack, host} ->
        if host == node() do
          apply(m,f,a)
        else
          :rpc.call(host, m,f,a, timeout)
        end
      o -> o
    end
  end

  def default_cast_to_host(mod, worker_lookup_handler, ref, {m,f,a}, context, options) do
    case worker_lookup_handler.host!(ref, mod, context, options) do
      {:ack, host} ->
        if host == node() do
          apply(m,f,a)
        else
          :rpc.cast(host, m,f,a)
        end
      o ->
        o
    end
  end

  #-------------------------------------------------------------------------
  # get_direct_link!
  #-------------------------------------------------------------------------
  def default_get_direct_link!(mod, ref, context, options \\ %{spawn: false}) do
    case  mod.worker_ref!(ref, context) do
      nil ->
        %Link{ref: ref, handler: mod, handle: nil, state: {:error, :no_ref}}
      {:error, details} ->
        %Link{ref: ref, handler: mod, handle: nil, state: {:error, details}}
      ref ->
        options_b = if Map.has_key?(options, :spawn) do
          options
        else
          put_in(options, [:spawn], false)
        end

        case mod.worker_pid!(ref, context, options_b) do
          {:ack, pid} ->
            %Link{ref: ref, handler: mod, handle: pid, state: :valid}
          {:error, details} ->
            %Link{ref: ref, handler: mod, handle: nil, state: {:error, details}}
          error ->
            %Link{ref: ref, handler: mod, handle: nil, state: {:error, error}}
        end
    end
  end

  #-------------------------------------------------------------------------
  # s_call unsafe implementations
  #-------------------------------------------------------------------------
  def default_s_call_unsafe(mod, ref, extended_call, context, options, timeout) do
    timeout = options[:timeout] || timeout
    case mod.worker_pid!(ref, context, options) do
      {:ack, pid} ->
        case GenServer.call(pid, extended_call, timeout) do
          :s_retry ->
            case mod.worker_pid!(ref, context, options) do
              {:ack, pid} ->
                GenServer.call(pid, extended_call, timeout)
              error -> error
            end
          v ->
            v
        end
      error ->
        error
    end # end case
  end #end s_call_unsafe

  def default_s_cast_unsafe(mod, ref, extended_call, context, options) do
    case mod.worker_pid!(ref, context, options) do
      {:ack, pid} -> GenServer.cast(pid, extended_call)
      error ->
        error
    end
  end


  def default_crash_protection_rs_call!({mod, base, worker_lookup_handler, s_redirect_feature}, identifier, call, context, options, timeout) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_call!, {mod, identifier, timeout}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_call_unsafe(identifier, extended_call, context, options, timeout)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: timeout, call: extended_call}, context, options)
              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do
              Logger.warn fn -> base.banner("#{mod}.s_call! - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              {:error, {:exit, o}}
            catch
              :exit, e ->
                {:error, {:exit, e}}
            end # end inner try
        end
    end # end try
  end

  @doc """
    Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
  """
  def default_crash_protection_s_call!(mod, identifier, call, context , options, timeout) do
    case  mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        try do
          options_b = put_in(options, [:spawn], true)
          mod.run_on_host(ref, {mod, :rs_call!, [ref, call, context, options_b, timeout]}, context, options_b, timeout)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end # end s_call!


  def default_crash_protection_rs_cast!({mod, base, worker_lookup_handler, s_redirect_feature}, identifier, call, context, options) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast!, {mod, identifier}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_cast_unsafe(identifier, extended_call, context, options)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: c, call: extended_call}, context, options)
              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do
              Logger.warn fn -> base.banner("#{mod}.s_cast! - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              {:error, {:exit, o}}
            catch
              :exit, e ->
                {:error, {:exit, e}}
            end # end inner try
        end
    end # end try
  end

  @doc """
    Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
  """
  def default_crash_protection_s_cast!(mod, identifier, call, context, options) do
    case  mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        try do
          options_b = put_in(options, [:spawn], true)
          mod.cast_to_host(ref, {mod, :rs_cast!, [ref, call, context, options_b]}, context, options_b)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end # end s_cast!

  def default_crash_protection_rs_call({mod, base, worker_lookup_handler, s_redirect_feature}, identifier, call, context, options, timeout) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_call, {mod, identifier, timeout}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_call_unsafe(identifier, extended_call, context, options, timeout)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: timeout, call: extended_call}, context, options)
              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do
              Logger.warn fn -> base.banner("#{mod}.s_call - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              {:error, {:exit, o}}
            catch
              :exit, e ->
                {:error, {:exit, e}}
            end # end inner try
        end
    end # end try
  end

  @doc """
    Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
  """
  def default_crash_protection_s_call(mod, identifier, call, context, options, timeout) do
    case  mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        try do
          options_b = put_in(options, [:spawn], false)
          mod.run_on_host(ref, {mod, :rs_call, [ref, call, context, options_b, timeout]}, context, options_b, timeout)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end # end s_call!

  def default_crash_protection_rs_cast({mod, base, worker_lookup_handler, s_redirect_feature}, identifier, call, context, options) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast, {mod, identifier}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_cast_unsafe(identifier, extended_call, context, options)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: c, call: extended_call}, context, options)
              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do
              Logger.warn fn -> base.banner("#{mod}.s_call! - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              {:error, {:exit, o}}
            catch
              :exit, e ->
                {:error, {:exit, e}}
            end # end inner try
        end
    end # end try
  end

  @doc """
    Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
  """
  def default_crash_protection_s_cast(mod, identifier, call, context, options) do
    case  mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        try do
          options_b = put_in(options, [:spawn], false)
          mod.cast_to_host(ref, {mod, :rs_cast, [ref, call, context, options_b]}, context, options_b)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end # end s_cast!



  @doc """
    Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
  """
  def default_nocrash_protection_s_call!({mod, s_redirect_feature}, identifier, call, context, options, timeout ) do
    case mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_call!, {mod, ref, timeout}, {:s, call, context}}, else: {:s, call, context}
        options_b = put_in(options, [:spawn], true)
        mod.run_on_host(ref, {mod, :s_call_unsafe, [ref, extended_call, context, options_b, timeout]}, context, options_b, timeout)
    end
  end # end s_call!

  @doc """
    Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
  """
  def default_nocrash_protection_s_cast!({mod, s_redirect_feature}, identifier, call, context, options) do
    case mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast!, {mod, ref}, {:s, call, context}}, else: {:s, call, context}
        options_b = put_in(options, [:spawn], true)
        mod.cast_to_host(ref, {__MODULE__, :s_cast_unsafe, [ref, extended_call, context, options_b]}, context, options_b)
    end # end case worker_ref!
  end # end s_cast!

  @doc """
    Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
  """
  def default_nocrash_protection_s_call({mod, s_redirect_feature}, identifier, call, context, options, timeout ) do
    case  mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_call, {mod, ref, timeout}, {:s, call, context}}, else: {:s, call, context}
        options_b = put_in(options, [:spawn], false)
        mod.run_on_host(ref, {__MODULE__, :s_call_unsafe, [ref, extended_call, context, options_b, timeout]}, context, options_b, timeout)
    end # end case
  end # end s_call!

  @doc """
    Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
  """
  def default_nocrash_protection_s_cast({mod, s_redirect_feature}, identifier, call, context, options) do
    case mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast, {mod, ref}, {:s, call, context}}, else: {:s, call, context}
        options_b = put_in(options, [:spawn], false)
        mod.cast_to_host(ref, {__MODULE__, :s_cast_unsafe, [ref, extended_call, context, options_b]}, context, options_b)
    end # end case worker_ref!
  end # end s_cast!


  @doc """
    Crash Protection always enabled, for now.
  """
  def default_link_forward!({mod, base, s_redirect_feature}, %Link{handler: __MODULE__} = link, call, context, options) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast, {mod, link.ref}, {:s, call, context}}, else: {:s, call, context}
    now_ts = options[:time] || :os.system_time(:seconds)
    options_b = put_in(options, [:spawn], true)

    try do
      if link.handle && (link.expire == :infinity or link.expire > now_ts) do
        GenServer.cast(link.handle, extended_call)
        {:ok, link}
      else
        case mod.worker_pid!(link.ref, context, options_b) do
          {:ack, pid} ->
            GenServer.cast(pid, extended_call)
            rc = if link.update_after == :infinity, do: :infinity, else: now_ts + link.update_after
            {:ok, %Link{link| handle: pid, state: :valid, expire: rc}}
          {:error, details} ->
            {:error, %Link{link| handle: nil, state: {:error, details}}}
        end # end case worker_pid!
      end # end if else
    catch
      :exit, e ->
        try do
          Logger.warn(fn -> {base.banner("#{__MODULE__}.s_forward - dead worker (#{inspect link})\n\n"),  Noizu.ElixirCore.CallingContext.metadata(context)} end )
          {:error, %Link{link| handle: nil, state: {:error, {:exit, e}}}}
        catch
          :exit, e ->
            {:error, %Link{link| handle: nil, state: {:error, {:exit, e}}}}
        end # end inner try
    end # end try
  end # end link_forward!


  #=================================================================
  #=================================================================
  # @__using__
  #=================================================================
  #=================================================================

  defmacro __using__(options) do
    option_settings = prepare_options(options)
    options = option_settings.effective_options
    required = options.required
    verbose = options.verbose
    worker_lookup_handler = options.worker_lookup_handler
    default_timeout = options.default_timeout
    shutdown_timeout = options.shutdown_timeout
    server_monitor = options.server_monitor

    case Map.keys(option_settings.output.errors) do
      [] -> :ok
      l when is_list(l) ->
        Logger.error "
    ---------------------- Errors In Pool Settings  ----------------------------
    #{inspect option_settings, pretty: true, limit: :infinity}
    ----------------------------------------------------------------------------
        "
    end

    features = MapSet.new(options.features)
    quote do
      require Logger
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.ServerBehaviour
      use GenServer
      @base (Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat)
      @worker (Module.concat([@base, "Worker"]))
      @worker_supervisor (Module.concat([@base, "WorkerSupervisor"]))
      @server (__MODULE__)
      @pool_supervisor (Module.concat([@base, "PoolSupervisor"]))
      @pool_async_load (unquote(Map.get(options, :async_load, false)))
      @simple_pool_group ({@base, @worker, @worker_supervisor, __MODULE__, @pool_supervisor})

      @worker_state_entity (Noizu.SimplePool.Behaviour.expand_worker_state_entity(@base, unquote(options.worker_state_entity)))
      @server_provider (unquote(options.server_provider))
      @worker_lookup_handler (unquote(worker_lookup_handler))
      @module_and_lookup_handler ({__MODULE__, @worker_lookup_handler})

      @timeout (unquote(default_timeout))
      @shutdown_timeout (unquote(shutdown_timeout))

      @base_verbose unquote(verbose)

      @server_monitor unquote(server_monitor)
      @option_settings unquote(Macro.escape(option_settings))
      @options unquote(Macro.escape(options))
      @s_redirect_feature unquote(MapSet.member?(features, :s_redirect))

      @graceful_stop unquote(MapSet.member?(features, :graceful_stop))

      def verbose() do
        default_verbose(@base_verbose, @base)
      end

      alias Noizu.SimplePool.Worker.Link
      def worker_state_entity, do: @worker_state_entity
      def option_settings, do: @option_settings
      def options, do: @options

      #=========================================================================
      # Genserver Lifecycle
      #=========================================================================
      if unquote(required.start_link) do
        def start_link(sup) do
          if verbose() do
            Logger.info(fn -> @base.banner("START_LINK #{__MODULE__} (#{inspect @worker_supervisor})@#{inspect self()}") end)
          end
          GenServer.start_link(__MODULE__, @worker_supervisor, name: __MODULE__)
        end
      end # end start_link

      if (unquote(required.init)) do
        def init(sup) do
          if verbose() do
            Logger.info(fn -> @base.banner("INIT #{__MODULE__} (#{inspect @worker_supervisor}@#{inspect self()})") end)
          end
          @server_provider.init(__MODULE__, @worker_supervisor, option_settings())
        end
      end # end init

      if (unquote(required.terminate)) do
        def terminate(reason, state), do: @server_provider.terminate(reason, state)
      end # end terminate

      def enable_server!(elixir_node) do
        @worker_lookup_handler.enable_server!(@base, elixir_node)
      end

      def disable_server!(elixir_node) do
        @worker_lookup_handler.disable_server!(@base, elixir_node)
      end

      def worker_sup_start(ref, transfer_state, sup, context) do
        childSpec = @worker_supervisor.child(ref, transfer_state, context)
        case Supervisor.start_child(@worker_supervisor, childSpec) do
          {:ok, pid} -> {:ack, pid}
          {:error, {:already_started, pid}} ->
            timeout = @timeout
            call = {:transfer_state, transfer_state}
            extended_call = if @s_redirect_feature, do: {:s_call!, {__MODULE__, ref, timeout}, {:s, call, context}}, else: {:s, call, context}
            GenServer.cast(pid, extended_call)
            Logger.warn(fn ->"#{__MODULE__} attempted a worker_transfer on an already running instance. #{inspect ref} -> #{inspect node()}@#{inspect pid}" end)
            {:ack, pid}
          {:error, :already_present} ->
            # We may no longer simply restart child as it may have been initilized
            # With transfer_state and must be restarted with the correct context.
            Supervisor.delete_child(@worker_supervisor, ref)
            case Supervisor.start_child(@worker_supervisor, childSpec) do
              {:ok, pid} -> {:ack, pid}
              error -> error
            end
          error -> error
        end # end case
      end # endstart/3

      def worker_sup_start(ref, sup, context) do
        childSpec = @worker_supervisor.child(ref, context)
        case Supervisor.start_child(@worker_supervisor, childSpec) do
          {:ok, pid} -> {:ack, pid}
          {:error, {:already_started, pid}} ->
            {:ack, pid}
          {:error, :already_present} ->
            # We may no longer simply restart child as it may have been initilized
            # With transfer_state and must be restarted with the correct context.
            Supervisor.delete_child(@worker_supervisor, ref)
            case Supervisor.start_child(@worker_supervisor, childSpec) do
              {:ok, pid} -> {:ack, pid}
              error -> error
            end
          error -> error
        end # end case
      end # endstart/3


      def worker_sup_start(ref, context) do
        childSpec = @worker_supervisor.child(ref, context)
        case Supervisor.start_child(@worker_supervisor, childSpec) do
          {:ok, pid} -> {:ack, pid}
          {:error, {:already_started, pid}} ->
            {:ack, pid}
          {:error, :already_present} ->
            # We may no longer simply restart child as it may have been initilized
            # With transfer_state and must be restarted with the correct context.
            Supervisor.delete_child(@worker_supervisor, ref)
            case Supervisor.start_child(@worker_supervisor, childSpec) do
              {:ok, pid} -> {:ack, pid}
              error -> error
            end
          error -> error
        end # end case
      end # endstart/3


      def worker_sup_terminate(ref, sup, context, options \\ %{}) do
        Supervisor.terminate_child(@worker_supervisor, ref)
        Supervisor.delete_child(@worker_supervisor, ref)
      end # end remove/3

      def worker_sup_remove(ref, sup, context, options \\ %{}) do
        g = if Map.has_key(options, :graceful_stop), do: options[:graceful_stop], else: @graceful_stop
        if g do
          s_call(ref, {:shutdown, [force: true]}, context, @shutdown_timeout)
        end
        Supervisor.terminate_child(@worker_supervisor, ref)
        Supervisor.delete_child(@worker_supervisor, ref)
      end # end remove/3

      #=========================================================================
      #
      #=========================================================================
      def worker_lookup_handler(), do: @worker_lookup_handler
      def base(), do: @base
      #-------------------------------------------------------------------------------
      # Startup: Lazy Loading/Async Load/Immediate Load strategies. Blocking/Lazy Initialization, Loading Strategy.
      #-------------------------------------------------------------------------------
      if unquote(required.status) do
        def status(context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: @server_provider.status(__MODULE__, context)
      end

      if unquote(required.load) do
        def load(context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: @server_provider.load(__MODULE__, context, options)
      end

      if unquote(required.load_complete) do
        def load_complete(process, context, state), do: @server_provider.load_complete(process, context, state)
      end

      if unquote(required.ref) do
        def ref(identifier), do: @worker_state_entity.ref(identifier)
      end

      #-------------------------------------------------------------------------------
      # Worker Process Management
      #-------------------------------------------------------------------------------
      if unquote(required.worker_add!) do
        def worker_add!(ref, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          options_b = put_in(options, [:spawn], true)
          ref = worker_ref!(ref)
          @worker_lookup_handler.process!(ref, __MODULE__, context, options_b)
        end
      end

      def run_on_host(ref, {m,f,a}, context, options \\ %{}, timeout \\ 30_000) do
        default_run_on_host(__MODULE__, @worker_lookup_handler, ref, {m,f,a}, context, options, timeout)
      end

      def cast_to_host(ref, {m,f,a}, context, options \\ %{}) do
        default_cast_to_host(__MODULE__, @worker_lookup_handler, ref, {m,f,a}, context, options)
      end

      if unquote(required.remove!) do
        def remove!(ref, context, options) do
          run_on_host(ref, {__MODULE__, :r_remove!, [ref, context, options]}, context, options)
        end

        def r_remove!(ref, context, options) do
          options_b = put_in(options, [:lock], %{type: :reap, for: 60})
          case @worker_lookup_handler.obtain_lock!(ref, context, options) do
            {:ack, _lock} -> worker_sup_remove(ref, @worker_supervisor, context, options)
            o -> o
          end
        end
      end

      if unquote(required.terminate!) do
        def terminate!(ref, context, options) do
          run_on_host(ref, {__MODULE__, :r_terminate!, [ref, context, options]}, context, options)
        end

        def r_terminate!(ref, context, options) do
          options_b = put_in(options, [:lock], %{type: :reap, for: 60})
          case @worker_lookup_handler.obtain_lock!(ref, context, options) do
            {:ack, _lock} -> worker_sup_terminate(ref, @worker_supervisor, context, options)
            o -> o
          end
        end
      end

      if unquote(required.worker_start_transfer!) do
        def worker_start_transfer!(ref, rebase, transfer_state, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          #if Node.ping(rebase) == :pong do
          #  if options[:async] do
          #    :rpc.cast(rebase, @server_provider, :offthread_worker_add!, [ref, transfer_state, options, context, @pool_async_load, __MODULE__, @pool_supervisor])
          #  else
          #    :rpc.call(rebase, @server_provider, :offthread_worker_add!, [ref, transfer_state, options, context, @pool_async_load, __MODULE__, @pool_supervisor])
          #  end
          #else
          #  {:error, {:pang, rebase}}
          #end
          raise "pri-1"
        end
      end

      if unquote(required.worker_migrate!) do
        def worker_migrate!(ref, rebase, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do

          """

          ref = worker_ref!(ref)
          case worker_pid!(ref, nil, context) do
            {:ok, pid} ->
              if options[:async] do
                s_cast!(ref, {:migrate!, ref, rebase, options}, context)
              else
                s_call!(ref, {:migrate!, ref, rebase, options}, context, options[:timeout] || 60_000)
              end
            o ->
              if (Node.ping(rebase) == :pong) do
                if options[:async] do
                  :rpc.cast(rebase, @server_provider, :offthread_worker_add!, [ref, options, context, @pool_async_load, __MODULE__, @pool_supervisor])
                  #remote_cast(rebase, {:worker_add!, ref, options}, context)
                else
                  :rpc.call(rebase, @server_provider, :offthread_worker_add!, [ref, options, context, @pool_async_load, __MODULE__, @pool_supervisor])
                  #remote_call(rebase, {:worker_add!, ref, options}, context, options[:timeout] || 60_000)
                end
              else
                {:error, {:pang, rebase}}
              end
          end
          """
          raise "pri-1"
        end
      end

      if unquote(required.worker_load!) do
        def worker_load!(ref, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: s_cast!(ref, {:load, options}, context)
      end

      if unquote(required.worker_ref!) do
        def worker_ref!(identifier, _context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: @worker_state_entity.ref(identifier)
      end

      if unquote(required.worker_pid!) do
        def worker_pid!(ref, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          @worker_lookup_handler.process!(ref, __MODULE__, context, options)
        end
      end

      @doc """
        Forward a call to the appropriate GenServer instance for this __MODULE__.
        @TODO add support for directing calls to specific nodes for load balancing purposes.
        @TODO add support for s_redirect
      """
      def self_call(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), timeout \\ @timeout) do
        case @server_monitor.supported_node(node(), @base, context) do
          :ack ->
            extended_call = {:s, call, context}
            GenServer.call(__MODULE__, extended_call, timeout)
          v -> {:error, v}
        end
      end
      def self_cast(call, context \\ Noizu.ElixirCore.CallingContext.system(%{})) do
        case @server_monitor.supported_node(node(), @base, context) do
          :ack ->
            extended_call = {:s, call, context}
            GenServer.cast(__MODULE__, extended_call)
          v -> {:error, v}
        end
      end

      def internal_call(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), timeout \\ @timeout) do
        case @server_monitor.supported_node(node(), @base, context) do
          :ack ->
            extended_call = {:i, call, context}
            GenServer.call(__MODULE__, extended_call, timeout)
          v -> {:error, v}
        end
      end

      def internal_cast(call, context \\ Noizu.ElixirCore.CallingContext.system(%{})) do
        case @server_monitor.supported_node(node(), @base, context) do
          :ack ->
            extended_call = {:i, call, context}
            GenServer.cast(__MODULE__, extended_call)
          v -> {:error, v}
        end
      end

      def remote_call(remote_node, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), timeout \\ @timeout) do
        case @server_monitor.supported_node(remote_node, @base, context) do
          :ack ->
            extended_call = {:i, call, context}
            if remote_node == node() do
              GenServer.call(__MODULE__, extended_call, timeout)
            else
              GenServer.call({__MODULE__, remote_node}, extended_call, timeout)
            end
          v -> {:error, v}
        end
      end

      def remote_cast(remote_node, call, context \\ Noizu.ElixirCore.CallingContext.system(%{})) do
        case @server_monitor.supported_node(remote_node, @base, context) do
          :ack ->
            extended_call = {:i, call, context}
            extended_call = {:i, call, context}
            if remote_node == node() do
              GenServer.cast(__MODULE__, extended_call)
            else
              GenServer.cast({__MODULE__, remote_node}, extended_call)
            end
          v -> {:error, v}
        end
      end

      #-------------------------------------------------------------------------
      # s_redirect
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :s_redirect)) || unquote(MapSet.member?(features, :s_redirect_handle)) do
        def handle_cast({_type, {__MODULE__, _ref}, call}, state), do: handle_cast(call, state)
        def handle_call({_type, {__MODULE__, _ref}, call}, from, state), do: handle_call(call, from, state)

        def handle_cast({:redirect, {_type, {__MODULE__, _ref}, call}}, state), do: handle_cast(call, state)
        def handle_call({:redirect, {_type, {__MODULE__, _ref}, call}}, from, state), do: handle_call(call, from, state)

        def handle_cast({:s_cast, {call_server, ref}, {:s, _inner, context} = call}, state) do
          Logger.warn fn -> "Redirecting Cast #{inspect call, pretty: true}\n\n"  end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:noreply, state}
        end # end handle_cast/:s_cast

        def handle_cast({:s_cast!, {call_server, ref}, {:s, _inner, context} = call}, state) do
          Logger.warn fn -> "Redirecting Cast #{inspect call, pretty: true}\n\n"  end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:noreply, state}
        end # end handle_cast/:s_cast!

        def handle_call({:s_call, {call_server, ref, timeout}, {:s, _inner, context} = call}, from, state) do
          Logger.warn fn -> "Redirecting Call #{inspect call, pretty: true}\n\n"  end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:reply, :s_retry, state}
        end # end handle_call/:s_call

        def handle_call({:s_call!, {call_server, ref, timeout}, {:s, _inner, context}} = call, from, state) do
          Logger.warn "Redirecting Call #{inspect call, pretty: true}\n\n"
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:reply, :s_retry, state}
        end # end handle_call/:s_call!

        def handle_cast({:redirect,  {:s_cast, {call_server, ref}, {:s, _inner, context} = call}} = fc, state) do
          Logger.error "Redirecting Cast Failed! #{inspect fc, pretty: true}\n\n"
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:noreply, state}
        end # end handle_cast/:s_cast

        def handle_cast({:redirect,  {:s_cast!, {call_server, ref}, {:s, _inner, context} = call}} = fc, state) do
          Logger.error "Redirecting Cast Failed! #{inspect fc, pretty: true}\n\n"
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:noreply, state}
        end # end handle_cast/:s_cast!

        def handle_call({:redirect, {:s_call, {call_server, ref, timeout}, {:s, _inner, context} = call}} = fc, from, state) do
          Logger.error "Redirecting Call Failed! #{inspect fc, pretty: true}\n\n"
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:reply, :s_retry, state}
        end # end handle_call/:s_call

        def handle_call({:redirect, {:s_call!, {call_server, ref, timeout}, {:s, _inner, context} = call}} = fc, from, state) do
          Logger.error "Redirecting Call Failed! #{inspect fc, pretty: true}\n\n"
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:reply, :s_retry, state}
        end # end handle_call/:s_call!
      end # if feature.s_redirect

      #-------------------------------------------------------------------------
      # fetch
      #-------------------------------------------------------------------------

      def fetch(identifier, fetch_options \\ %{}, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: s_call!(identifier, {:fetch, fetch_options}, context, options)

      if unquote(required.save!) do
        def save!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: s_call!(identifier, :save!, context)
        def save_async!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: s_cast!(identifier, :save!, context)
      end

      if unquote(required.reload!) do
        def reload!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: s_call!(identifier, {:reload!, options}, context)
        def reload_async!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: s_cast!(identifier, {:reload!, options}, context)
      end

      if unquote(required.ping!) do
        def ping!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), timeout \\ @timeout), do: s_call!(identifier, :ping!, context, timeout)
      end

      if unquote(required.kill!) do
        def kill!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: s_cast!(identifier, :kill!, context)
      end

      if unquote(required.crash!) do
        def crash!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ :%{}), do: s_cast!(identifier, {:crash!, options}, context)
      end

      if unquote(required.health_check!) do
        def health_check!(identifier,  context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ :default, timeout \\ @timeout), do: s_call!(identifier, {:health_check!, options}, context, timeout)
      end

      #-------------------------------------------------------------------------
      # get_direct_link!
      #-------------------------------------------------------------------------
      def get_direct_link!(ref, context, options \\ %{spawn: false}) do
        default_get_direct_link!(__MODULE__, ref, context, options)
      end

      #-------------------------------------------------------------------------
      # s_call unsafe implementations
      #-------------------------------------------------------------------------
      def s_call_unsafe(ref, extended_call, context, options, timeout \\ @timeout) do
        default_s_call_unsafe(__MODULE__, ref, extended_call, context, options, timeout)
      end #end s_call_unsafe

      def s_cast_unsafe(ref, extended_call, context, options) do
        default_s_cast_unsafe(__MODULE__, ref, extended_call, context, options)
      end

      if unquote(MapSet.member?(features, :crash_protection)) do
        def rs_call!(identifier, call, context, options, timeout) do
          default_crash_protection_rs_call!({__MODULE__, @base, @worker_lookup_handler, @s_redirect_feature}, identifier, call, context, options, timeout)
        end

        @doc """
          Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
        """
        def s_call!(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}, timeout \\ @timeout) do
          default_crash_protection_s_call!(__MODULE__, identifier, call, context , options, timeout)
        end # end s_call!


        def rs_cast!(identifier, call, context, options) do
          default_crash_protection_rs_cast!({__MODULE__, @base, @worker_lookup_handler, @s_redirect_feature}, identifier, call, context, options)
        end

        @doc """
          Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
        """
        def s_cast!(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          default_crash_protection_s_cast!(__MODULE__, identifier, call, context, options)
        end # end s_cast!

        def rs_call(identifier, call, context, options, timeout) do
          default_crash_protection_rs_call({__MODULE__, @base, @worker_lookup_handler, @s_redirect_feature}, identifier, call, context, options, timeout)
        end

        @doc """
          Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
        """
        def s_call(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}, timeout \\ @timeout) do
          default_crash_protection_s_call(__MODULE__, identifier, call, context, options, timeout)
        end # end s_call!

        def rs_cast(identifier, call, context, options) do
          default_crash_protection_rs_cast({__MODULE__, @base, @worker_lookup_handler, @s_redirect_feature}, identifier, call, context, options)
        end


        @doc """
          Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
        """
        def s_cast(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          default_crash_protection_s_cast(__MODULE__, identifier, call, context, options)
        end # end s_cast!


      else # no crash_protection

        @doc """
          Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
        """
        def s_call!(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}, timeout \\ @timeout) do
          default_nocrash_protection_s_call!({__MODULE__, @s_redirect_feature}, identifier, call, context, options, timeout)
        end # end s_call!

        @doc """
          Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
        """
        def s_cast!(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{})) do
          default_nocrash_protection_s_cast!({__MODULE__, @s_redirect_feature}, identifier, call, context, options)
        end # end s_cast!

        @doc """
          Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
        """
        def s_call(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), timeout \\ @timeout) do
          default_nocrash_protection_s_call({__MODULE__, @s_redirect_feature}, identifier, call, context, options, timeout )
        end # end s_call!

        @doc """
          Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
        """
        def s_cast(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), optiosn \\ %{}) do
          default_nocrash_protection_s_cast({__MODULE__, @s_redirect_feature}, identifier, call, context, options)
        end # end s_cast!
      end # end if feature.crash_protection

      if unquote(required.link_forward!) do
        @doc """
          Crash Protection always enabled, for now.
        """
        def link_forward!(%Link{handler: __MODULE__} = link, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          default_link_forward!({__MODULE__, @base, @s_redirect_feature}, link, call, context, options)
        end # end link_forward!
      end # end if required link_forward!

      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do


      #-------------------------------------------------------------------------------
      # Internal Forwarding
      #-------------------------------------------------------------------------------
      def handle_call({:i, call, context}, from, state), do: @server_provider.internal_call_handler(call, context, from, state)
      def handle_cast({:i, call, context}, state), do: @server_provider.internal_cast_handler(call, context, state)
      def handle_info({:i, call, context}, state), do: @server_provider.internal_info_handler(call, context, state)

      #-------------------------------------------------------------------------------
      # Catch All
      #-------------------------------------------------------------------------------
      def handle_call(uncaught, _from, state) do
        Logger.warn("Uncaught handle_call to #{__MODULE__} . . . #{inspect uncaught}")
        {:noreply, state}
      end

      def handle_cast(uncaught, state) do
        Logger.warn("Uncaught handle_cast to #{__MODULE__} . . . #{inspect uncaught}")
        {:noreply, state}
      end

      def handle_info(uncaught, state) do
        Logger.warn("Uncaught handle_info to #{__MODULE__} . . . #{inspect uncaught}")
        {:noreply, state}
      end

    end # end quote
  end # end __before_compile__




end
