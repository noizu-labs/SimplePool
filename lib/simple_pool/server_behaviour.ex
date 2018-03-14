#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.ServerBehaviour do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList
  alias Noizu.SimplePool.Worker.Link
  require Logger

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

              :active_supervisors, :supervisor_by_index, :available_supervisors, :current_supervisor, :count_supervisor_chidren
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
        default_definition: %OptionValue{option: :default_definition, default: :auto},
        server_driver: %OptionValue{option: :server_driver, default: Application.get_env(:noizu_simple_pool, :default_server_driver, Noizu.SimplePool.ServerDriver.Default)},
        worker_lookup_handler: %OptionValue{option: :worker_lookup_handler, default: Application.get_env(:noizu_simple_pool, :worker_lookup_handler, Noizu.SimplePool.WorkerLookupBehaviour.Default)},
        server_provider: %OptionValue{option: :server_provider, default: Application.get_env(:noizu_simple_pool, :default_server_provider, Noizu.SimplePool.Server.ProviderBehaviour.Default)},
        server_monitor:   %OptionValue{option: :server_monitor, default:  Application.get_env(:noizu_simple_pool, :default_server_monitr, Noizu.SimplePool.MonitoringFramework.MonitorBehaviour.Default)},
        log_timeouts: %OptionValue{option: :log_timeouts, default: Application.get_env(:noizu_simple_pool, :default_log_timeouts, true)}
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

  def default_run_on_host(mod, _base, worker_lookup_handler, ref, {m,f,a}, context, options \\ %{}, timeout \\ 30_000) do
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

  def default_cast_to_host(mod, _base, worker_lookup_handler, ref, {m,f,a}, context, options) do
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
  # default_bulk_migrate!
  #-------------------------------------------------------------------------
  def default_bulk_migrate!(mod, transfer_server, context, options) do
    tasks = if options[:sync] do
      to = options[:timeout] || 60_000
      options_b = put_in(options, [:timeout], to)

      Task.async_stream(transfer_server, fn({server, refs}) ->
                                           o = Task.async_stream(refs, fn(ref) ->
                                                                         {ref, mod.o_call(ref, {:migrate!, ref, server, options_b}, context, options_b, to)}
                                           end, timeout: to)
                                           {server, o |> Enum.to_list()}
      end, timeout: to)
    else
      to = options[:timeout] || 60_000
      options_b = put_in(options, [:timeout], to)
      Task.async_stream(transfer_server, fn({server, refs}) ->
                                           o = Task.async_stream(refs, fn(ref) ->
                                                                         {ref, mod.o_cast(ref, {:migrate!, ref, server, options_b}, context)}
                                           end, timeout: to)
                                           {server, o |> Enum.to_list()}
      end, timeout: to)
    end

    r = Enum.reduce(tasks, %{}, fn(task_outcome, acc) ->
      case task_outcome do
        {:ok, {server, outcome}} ->
          put_in(acc, [server], outcome)
        _error -> acc
      end
    end)

    {:ack, r}
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
          v -> v
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


  def default_crash_protection_rs_call!({mod, base, worker_lookup_handler, s_redirect_feature, log_timeout}, identifier, call, context, options, timeout) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_call!, {mod, identifier, timeout}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_call_unsafe(identifier, extended_call, context, options, timeout)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: timeout, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call! - timeout.\n call: #{inspect extended_call}") end
              end
              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do

              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call! - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              end
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
    case mod.worker_ref!(identifier, context) do
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

  def default_crash_protection_rs_cast!({mod, base, worker_lookup_handler, s_redirect_feature, log_timeout}, identifier, call, context, options) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast!, {mod, identifier}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_cast_unsafe(identifier, extended_call, context, options)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: c, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_cast! - timeout.\n call: #{inspect extended_call}") end

              end
              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_cast! - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              end

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

  def default_crash_protection_rs_call({mod, base, worker_lookup_handler, s_redirect_feature, log_timeout}, identifier, call, context, options, timeout) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_call, {mod, identifier, timeout}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_call_unsafe(identifier, extended_call, context, options, timeout)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: timeout, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call - timeout.\n call: #{inspect extended_call}") end
              end

              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              end
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

  def default_crash_protection_rs_cast({mod, base, worker_lookup_handler, s_redirect_feature, log_timeout}, identifier, call, context, options) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast, {mod, identifier}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_cast_unsafe(identifier, extended_call, context, options)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: c, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call! - timeout.\n call: #{inspect extended_call}") end
              end
              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call! - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              end
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
    @TODO links should be allowed in place of refs.
    @TODO forward should handle cast, call and info forwarding
  """
  def default_link_forward!({mod, base, s_redirect_feature}, %Link{} = link, call, context, options) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast, {mod, link.ref}, {:s, call, context}}, else: {:s, call, context}
    now_ts = options[:time] || :os.system_time(:seconds)
    options_b = options #put_in(options, [:spawn], true)

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
          {:nack, details} -> {:error, %Link{link| handle: nil, state: {:error, {:nack, details}}}}
          {:error, details} ->
            {:error, %Link{link| handle: nil, state: {:error, details}}}
          error ->
            {:error, %Link{link| handle: nil, state: {:error, error}}}
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
    log_timeouts = options.log_timeouts
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
      alias Noizu.SimplePool.Worker.Link
      @behaviour Noizu.SimplePool.ServerBehaviour
      use GenServer
      @base (Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat)
      @worker (Module.concat([@base, "Worker"]))
      @worker_supervisor (Module.concat([@base, "WorkerSupervisor_S1"]))

      @worker_supervisors %{
        1 => Module.concat([@base, "WorkerSupervisor_S1"]),
        2 => Module.concat([@base, "WorkerSupervisor_S2"]),
        3 => Module.concat([@base, "WorkerSupervisor_S3"]),
        4 => Module.concat([@base, "WorkerSupervisor_S4"]),
        5 => Module.concat([@base, "WorkerSupervisor_S5"]),
        6 => Module.concat([@base, "WorkerSupervisor_S6"]),
        7 => Module.concat([@base, "WorkerSupervisor_S7"]),
        8 => Module.concat([@base, "WorkerSupervisor_S8"]),
        9 => Module.concat([@base, "WorkerSupervisor_S9"]),
        10 => Module.concat([@base, "WorkerSupervisor_S10"]),
        11 => Module.concat([@base, "WorkerSupervisor_S11"]),
        12 => Module.concat([@base, "WorkerSupervisor_S12"]),
        13 => Module.concat([@base, "WorkerSupervisor_S13"]),
        14 => Module.concat([@base, "WorkerSupervisor_S14"]),
        15 => Module.concat([@base, "WorkerSupervisor_S15"]),
        16 => Module.concat([@base, "WorkerSupervisor_S16"]),
        17 => Module.concat([@base, "WorkerSupervisor_S17"]),
        18 => Module.concat([@base, "WorkerSupervisor_S18"]),
        19 => Module.concat([@base, "WorkerSupervisor_S19"]),
        20 => Module.concat([@base, "WorkerSupervisor_S20"]),
      }

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

      @log_timeouts unquote(log_timeouts)

      @server_monitor unquote(server_monitor)
      @option_settings unquote(Macro.escape(option_settings))
      @options unquote(Macro.escape(options))
      @s_redirect_feature unquote(MapSet.member?(features, :s_redirect))
      @default_definition @options.default_definition

      @graceful_stop unquote(MapSet.member?(features, :graceful_stop))


      if (unquote(required.verbose)) do
        def verbose(), do: default_verbose(@base_verbose, @base)
      end

      if (unquote(required.option_settings)) do
        def option_settings(), do: @option_settings
      end

      if (unquote(required.options)) do
        def options(), do: @options
      end

      if (unquote(required.worker_state_entity)) do
        def worker_state_entity, do: @worker_state_entity
      end

      def handle_call({:m, {:status, options}, context}, _from, state) do
        {:reply, {:ack, state.environment_details.status}, state}
      end

      def default_definition() do
        case @default_definition do
          :auto ->
            a = %Noizu.SimplePool.MonitoringFramework.Service.Definition{
              identifier: {node(), base()},
              server: node(),
              pool: @server,
              supervisor: @pool_supervisor,
              time_stamp: DateTime.utc_now(),
              hard_limit: 0,
              soft_limit: 0,
              target: 0,
            }
            Application.get_env(:noizu_simple_pool, :definitions, %{})[base()] || a
          v -> v
        end
      end

      #=========================================================================
      # Multiple Supervisor Updated
      #=========================================================================
      if unquote(required.count_supervisor_chidren) do
        def count_supervisor_chidren() do
          Enum.reduce(available_supervisors(), %{active: 0, specs: 0, supervisors: 0, workers: 0}, fn(s, acc) ->
            u = Supervisor.count_children(s)
            %{acc| active: acc.active + u.active, specs: acc.specs + u.specs, supervisors: acc.supervisors + u.supervisors, workers: acc.workers + u.workers}
          end)
        end
      end

      if unquote(required.active_supervisors) do
        def active_supervisors() do
          e =  Application.get_env(:noizu_simple_pool, :num_supervisors, %{})
          num_supervisors = e[@base] || e[:default] || 1
        end
      end

      if unquote(required.supervisor_by_index) do
        def supervisor_by_index(index) do
          @worker_supervisors[index]
        end
      end

      if unquote(required.available_supervisors) do
        def available_supervisors() do
          Map.values(@worker_supervisors)
        end
      end

      if unquote(required.current_supervisor) do
        def current_supervisor(ref) do
          num_supervisors = active_supervisors()
          if num_supervisors == 1 do
            @worker_supervisor
          else
            hint = @worker_state_entity.supervisor_hint(ref)
            num_supervisors = active_supervisors()
            # The logic is designed so that the selected supervisor only changes for a subset of items when adding new supervisors
            # So that, for example, when going from 5 to 6 supervisors only a 6th of entries will be re-assigned to the new bucket.
            index = Enum.reduce(1 .. num_supervisors, 1, fn(x, acc) ->
              n = rem(hint, x) + 1
              (n == x) && n || acc
            end)
            supervisor_by_index(index)
          end
        end
      end

      #=========================================================================
      # Genserver Lifecycle
      #=========================================================================
      if unquote(required.start_link) do
        def start_link(sup, definition, context) do
          definition = if definition == :default do
            auto = default_definition()
            if verbose() do
              Logger.info(fn -> {@base.banner("START_LINK #{__MODULE__} (#{inspect @worker_supervisor})@#{inspect self()}\ndefinition: #{inspect definition}\ndefault: #{inspect auto}"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
            end
            auto
          else
            if verbose() do
              Logger.info(fn -> {@base.banner("START_LINK #{__MODULE__} (#{inspect @worker_supervisor})@#{inspect self()}\ndefinition: #{inspect definition}"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
            end
            definition
          end
          GenServer.start_link(__MODULE__, [:deprecated, definition, context], name: __MODULE__, restart: :permanent)
        end
      end # end start_link

      if (unquote(required.init)) do
        def init([_sup, definition, context] = args) do
          if verbose() do
            Logger.info(fn -> {@base.banner("INIT #{__MODULE__} (#{inspect @worker_supervisor}@#{inspect self()})\n args: #{inspect args, pretty: true}"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
          end
          @server_provider.init(__MODULE__, :deprecated, definition, context, option_settings())
        end
      end # end init

      if (unquote(required.terminate)) do
        def terminate(reason, state), do: @server_provider.terminate(__MODULE__, reason, state, nil, %{})
      end # end terminate

      if (unquote(required.enable_server!)) do
        def enable_server!(elixir_node) do
          #@TODO reimplement pri1
          #@server_monitor.enable_server!(@base, elixir_node)
          :pending
        end
      end

      if (unquote(required.disable_server!)) do
        def disable_server!(elixir_node) do
          #@TODO reimplement pri1
          #@server_monitor.disable_server!(@base, elixir_node)
          :pending
        end
      end

      if (unquote(required.worker_sup_start)) do
        def worker_sup_start(ref, transfer_state, context) do

          worker_sup = current_supervisor(ref)

          childSpec = worker_sup.child(ref, transfer_state, context)
          case Supervisor.start_child(worker_sup, childSpec) do
            {:ok, pid} -> {:ack, pid}
            {:error, {:already_started, pid}} ->
              timeout = @timeout
              call = {:transfer_state, {:state, transfer_state, time: :os.system_time(:second)}}
              extended_call = if @s_redirect_feature, do: {:s_call!, {__MODULE__, ref, timeout}, {:s, call, context}}, else: {:s, call, context}
              GenServer.cast(pid, extended_call)
              Logger.warn(fn ->"#{__MODULE__} attempted a worker_transfer on an already running instance. #{inspect ref} -> #{inspect node()}@#{inspect pid}" end)
              {:ack, pid}
            {:error, :already_present} ->
              # We may no longer simply restart child as it may have been initilized
              # With transfer_state and must be restarted with the correct context.
              Supervisor.delete_child(worker_sup, ref)
              case Supervisor.start_child(worker_sup, childSpec) do
                {:ok, pid} -> {:ack, pid}
                {:error, {:already_started, pid}} -> {:ack, pid}
                error -> error
              end
            error -> error
          end # end case
        end # endstart/3

        def worker_sup_start(ref, context) do
          worker_sup = current_supervisor(ref)
          childSpec = worker_sup.child(ref, context)
          case Supervisor.start_child(worker_sup, childSpec) do
            {:ok, pid} -> {:ack, pid}
            {:error, {:already_started, pid}} ->
              {:ack, pid}
            {:error, :already_present} ->
              # We may no longer simply restart child as it may have been initilized
              # With transfer_state and must be restarted with the correct context.
              Supervisor.delete_child(worker_sup, ref)
              case Supervisor.start_child(worker_sup, childSpec) do
                {:ok, pid} -> {:ack, pid}
                {:error, {:already_started, pid}} -> {:ack, pid}
                error -> error
              end
            error -> error
          end # end case
        end # endstart/3
      end

      if (unquote(required.worker_sup_terminate)) do
        def worker_sup_terminate(ref, sup, context, options \\ %{}) do
          worker_sup = current_supervisor(ref)
          Supervisor.terminate_child(worker_sup, ref)
          Supervisor.delete_child(worker_sup, ref)
        end # end remove/3
      end

      if (unquote(required.worker_sup_remove)) do
        def worker_sup_remove(ref, _sup, context, options \\ %{}) do
          g = if Map.has_key?(options, :graceful_stop), do: options[:graceful_stop], else: @graceful_stop
          if g do
            s_call(ref, {:shutdown, [force: true]}, context, options, @shutdown_timeout)
          end
          worker_sup = current_supervisor(ref)
          Supervisor.terminate_child(worker_sup, ref)
          Supervisor.delete_child(worker_sup, ref)
        end # end remove/3
      end

      #=========================================================================
      #
      #=========================================================================
      if (unquote(required.worker_lookup_handler)) do
        def worker_lookup_handler(), do: @worker_lookup_handler
      end

      if (unquote(required.base)) do
        def base(), do: @base
      end

      if (unquote(required.pool_supervisor)) do
        def pool_supervisor(), do: @pool_supervisor
      end

      #-------------------------------------------------------------------------------
      # Startup: Lazy Loading/Async Load/Immediate Load strategies. Blocking/Lazy Initialization, Loading Strategy.
      #-------------------------------------------------------------------------------
      if unquote(required.status) do
        def status(context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: @server_provider.status(__MODULE__, context)
      end

      if unquote(required.load) do
        def load(context \\ Noizu.ElixirCore.CallingContext.system(%{}), settings \\ %{}), do: @server_provider.load(__MODULE__, context, settings)
      end

      if unquote(required.load_complete) do
        def load_complete(this, process, context), do: @server_provider.load_complete(this, process, context)
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


      if (unquote(required.run_on_host)) do
        def run_on_host(ref, {m,f,a}, context, options \\ %{}, timeout \\ 30_000) do
          default_run_on_host(__MODULE__, @base, @worker_lookup_handler, ref, {m,f,a}, context, options, timeout)
        end
      end

      if (unquote(required.cast_to_host)) do
        def cast_to_host(ref, {m,f,a}, context, options \\ %{}) do
          default_cast_to_host(__MODULE__, @base, @worker_lookup_handler, ref, {m,f,a}, context, options)
        end
      end

      if unquote(required.remove!) do
        def remove!(ref, context, options) do
          run_on_host(ref, {__MODULE__, :r_remove!, [ref, context, options]}, context, options)
        end

        def r_remove!(ref, context, options) do
          options_b = put_in(options, [:lock], %{type: :reap, for: 60})
          case @worker_lookup_handler.obtain_lock!(ref, context, options) do
            {:ack, _lock} -> worker_sup_remove(ref, :deprecated, context, options)
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
            {:ack, _lock} -> worker_sup_terminate(ref, :deprecated, context, options)
            o -> o
          end
        end
      end

      if unquote(required.bulk_migrate!) do
        def bulk_migrate!(transfer_server, context, options) do
          default_bulk_migrate!(__MODULE__, transfer_server, context, options)
        end
      end

      if unquote(required.worker_migrate!) do
        def worker_migrate!(ref, rebase, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          if options[:sync] do
            s_call!(ref, {:migrate!, ref, rebase, options}, context, options, options[:timeout] || 60_000)
          else
            s_cast!(ref, {:migrate!, ref, rebase, options}, context)
          end
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
          @worker_lookup_handler.process!(ref, @base,  __MODULE__, context, options)
        end
      end

      if unquote(required.accept_transfer!) do
        def accept_transfer!(ref, state, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          options_b = options
                      |> put_in([:lock], %{type: :transfer})
          case @worker_lookup_handler.obtain_lock!(ref, context, options_b) do
            {:ack, lock} ->
              case worker_sup_start(ref, state, context) do
                {:ack, pid} ->
                  {:ack, pid}
                o -> {:error, {:worker_sup_start, o}}
              end
            o -> {:error, {:get_lock, o}}
          end
        end
      end

      if unquote(required.lock!) do
        def lock!(context, options \\ %{}), do: internal_system_call({:lock!, options}, context, options)
      end

      if unquote(required.release!) do
        def release!(context, options \\ %{}), do: internal_system_call({:release!, options}, context, options)
      end

      if unquote(required.status_wait) do
        def status_wait(target_state, context, timeout \\ :infinity)
        def status_wait(target_state, context, timeout) when is_atom(target_state) do
          status_wait(MapSet.new([target_state]), context, timeout)
        end

        def status_wait(target_state, context, timeout) when is_list(target_state) do
          status_wait(MapSet.new(target_state), context, timeout)
        end

        def status_wait(%MapSet{} = target_state, context, timeout) do
          if timeout == :infinity do
            case entity_status(context) do
              {:ack, state} -> if MapSet.member?(target_state, state), do: state, else: status_wait(target_state, context, timeout)
              _ -> status_wait(target_state, context, timeout)
            end
          else
            ts = :os.system_time(:millisecond)
            case entity_status(context, %{timeout: timeout}) do

              {:ack, state} ->
                if MapSet.member?(target_state, state) do
                  state
                else
                  t = timeout - (:os.system_time(:millisecond) - ts)
                  if t > 0 do
                    status_wait(target_state, context, t)
                  else
                    {:timeout, state}
                  end
                end
              v ->
                t = timeout - (:os.system_time(:millisecond) - ts)
                if t > 0 do
                  status_wait(target_state, context, t)
                else
                  {:timeout, v}
                end
            end
          end
        end
      end

      if unquote(required.entity_status) do
        def entity_status(context, options \\ %{}) do
          timeout = options[:timeout] || 5_000
          try do
            GenServer.call(__MODULE__, {:m, {:status, options}, context}, timeout)
          catch
            :exit, e ->
              case e do
                {:timeout, c} -> {:timeout, c}
              end
          end # end try
        end
      end

      if (unquote(required.self_call)) do
        @doc """
          Forward a call to the appropriate GenServer instance for this __MODULE__.
          @TODO add support for directing calls to specific nodes for load balancing purposes.
          @TODO add support for s_redirect
        """
        def self_call(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          #IO.puts "#{__MODULE__}.self_call #{inspect call}"
          case @server_monitor.supports_service?(node(), @base, context, options) do
            :ack ->
              extended_call = {:s, call, context}
              timeout = options[:timeout] || @timeout
              GenServer.call(__MODULE__, extended_call, timeout)
            v -> {:error, v}
          end
        end
      end

      if (unquote(required.self_cast)) do

        def self_cast(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          #IO.puts "#{__MODULE__}.self_cast #{inspect call}"
          case @server_monitor.supports_service?(node(), @base, context, options) do
            :ack ->
              extended_call = {:s, call, context}
              GenServer.cast(__MODULE__, extended_call)
            v -> {:error, v}
          end
        end
      end

      if (unquote(required.internal_system_call)) do
        def internal_system_call(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          options = put_in(options, [:system_call], true)
          internal_call(call, context, options)
        end
      end


      if (unquote(required.internal_system_cast)) do
        def internal_system_cast(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          options = put_in(options, [:system_call], true)
          internal_cast(call, context, options)
        end
      end

      if (unquote(required.internal_call)) do
        def internal_call(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          #IO.puts "#{__MODULE__}.internal_call #{inspect call} - #{inspect options}"
          case @server_monitor.supports_service?(node(), @base, context, options) do
            :ack ->
              extended_call = {:i, call, context}
              timeout = options[:timeout] || @timeout
              GenServer.call(__MODULE__, extended_call, timeout)
            v -> {:error, v}
          end
        end
      end

      if (unquote(required.internal_cast)) do
        def internal_cast(call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          #IO.puts "#{__MODULE__}.internal_cast #{inspect call}"
          case @server_monitor.supports_service?(node(), @base, context, options) do
            :ack ->
              extended_call = {:i, call, context}
              GenServer.cast(__MODULE__, extended_call)
            v -> {:error, v}
          end
        end
      end

      if (unquote(required.remote_system_call)) do
        def remote_system_call(remote_node, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          options = put_in(options, [:system_call], true)
          remote_call(remote_node, call, context, options)
        end
      end

      if (unquote(required.remote_system_cast)) do
        def remote_system_cast(remote_node, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          options = put_in(options, [:system_call], true)
          remote_cast(remote_node, call, context, options)
        end
      end

      if (unquote(required.remote_call)) do
        def remote_call(remote_node, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          #IO.puts "#{__MODULE__}.remote_call #{inspect call}"
          timeout = options[:timeout] || @timeout
          extended_call = {:i, call, context}
          if remote_node == node() do
            GenServer.call(__MODULE__, extended_call, timeout)
          else
            GenServer.call({__MODULE__, remote_node}, extended_call, timeout)
          end
        end
      end

      if (unquote(required.remote_cast)) do
        def remote_cast(remote_node, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          #IO.puts "#{__MODULE__}.remote_cast #{inspect call}"
          extended_call = {:i, call, context}
          if remote_node == node() do
            GenServer.cast(__MODULE__, extended_call)
          else
            GenServer.cast({__MODULE__, remote_node}, extended_call)
          end
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
          Logger.warn fn -> {"Redirecting Cast #{inspect call, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)}  end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:noreply, state}
        end # end handle_cast/:s_cast

        def handle_cast({:s_cast!, {call_server, ref}, {:s, _inner, context} = call}, state) do
          Logger.warn fn -> {"Redirecting Cast #{inspect call, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:noreply, state}
        end # end handle_cast/:s_cast!

        def handle_call({:s_call, {call_server, ref, timeout}, {:s, _inner, context} = call}, from, state) do
          Logger.warn fn -> {"Redirecting Call #{inspect call, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:reply, :s_retry, state}
        end # end handle_call/:s_call

        def handle_call({:s_call!, {call_server, ref, timeout}, {:s, _inner, context}} = call, from, state) do
          Logger.warn fn -> {"Redirecting Call #{inspect call, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:reply, :s_retry, state}
        end # end handle_call/:s_call!

        def handle_cast({:redirect,  {:s_cast, {call_server, ref}, {:s, _inner, context} = call}} = fc, state) do
          Logger.error fn -> {"Redirecting Cast Failed! #{inspect fc, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:noreply, state}
        end # end handle_cast/:s_cast

        def handle_cast({:redirect,  {:s_cast!, {call_server, ref}, {:s, _inner, context} = call}} = fc, state) do
          Logger.error fn -> {"Redirecting Cast Failed! #{inspect fc, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:noreply, state}
        end # end handle_cast/:s_cast!

        def handle_call({:redirect, {:s_call, {call_server, ref, timeout}, {:s, _inner, context} = call}} = fc, from, state) do
          Logger.error fn -> {"Redirecting Call Failed! #{inspect fc, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:reply, :s_retry, state}
        end # end handle_call/:s_call

        def handle_call({:redirect, {:s_call!, {call_server, ref, timeout}, {:s, _inner, context} = call}} = fc, from, state) do
          Logger.error fn -> { "Redirecting Call Failed! #{inspect fc, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
          call_server.worker_lookup_handler().unregister!(ref, context, %{})
          {:reply, :s_retry, state}
        end # end handle_call/:s_call!
      end # if feature.s_redirect

      #-------------------------------------------------------------------------
      # fetch
      #-------------------------------------------------------------------------
      if (unquote(required.fetch)) do
        def fetch(identifier, fetch_options \\ %{}, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: s_call!(identifier, {:fetch, fetch_options}, context, options)
      end

      if unquote(required.save!) do
        def save!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: s_call!(identifier, :save!, context, options)
        def save_async!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: s_cast!(identifier, :save!, context)
      end

      if unquote(required.reload!) do
        def reload!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: s_call!(identifier, {:reload!, options}, context, options)
        def reload_async!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: s_cast!(identifier, {:reload!, options}, context, options)
      end

      if unquote(required.ping!) do
        def ping!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          timeout = options[:timeout] || @timeout
          s_call(identifier, :ping!, context, options, timeout)
        end
      end

      if unquote(required.kill!) do
        def kill!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: s_cast!(identifier, :kill!, context, options)
      end

      if unquote(required.server_kill!) do
        def server_kill!(context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: internal_cast({:server_kill!, options}, context)
      end


      if unquote(required.crash!) do
        def crash!(identifier, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: s_cast!(identifier, {:crash!, options}, context, options)
      end

      if unquote(required.service_health_check!) do
        def service_health_check!(%Noizu.ElixirCore.CallingContext{} = context), do: internal_system_call({:health_check!, %{}}, context)
        def service_health_check!(health_check_options, %Noizu.ElixirCore.CallingContext{} = context), do: internal_system_call({:health_check!, health_check_options}, context)
        def service_health_check!(health_check_options, %Noizu.ElixirCore.CallingContext{} = context, options) do
          internal_system_call({:health_check!, health_check_options}, context, options)
        end
      end

      if unquote(required.health_check!) do
        def health_check!(identifier, %Noizu.ElixirCore.CallingContext{} = context), do: s_call!(identifier, {:health_check!, %{}}, context)
        def health_check!(identifier, health_check_options, %Noizu.ElixirCore.CallingContext{} = context), do: s_call!(identifier, {:health_check!, health_check_options}, context)
        def health_check!(identifier, health_check_options, %Noizu.ElixirCore.CallingContext{} = context, options), do: s_call!(identifier, {:health_check!, health_check_options}, context, options)
      end

      #-------------------------------------------------------------------------
      # get_direct_link!
      #-------------------------------------------------------------------------
      if (unquote(required.get_direct_link!)) do
        def get_direct_link!(ref, context, options \\ %{spawn: false}) do
          default_get_direct_link!(__MODULE__, ref, context, options)
        end
      end

      #-------------------------------------------------------------------------
      # s_call unsafe implementations
      #-------------------------------------------------------------------------
      if (unquote(required.s_call_unsafe)) do
        def s_call_unsafe(ref, extended_call, context, options \\ %{}, timeout \\ @timeout) do
          default_s_call_unsafe(__MODULE__, ref, extended_call, context, options, timeout)
        end #end s_call_unsafe
      end

      if (unquote(required.s_cast_unsafe)) do
        def s_cast_unsafe(ref, extended_call, context, options \\ %{}) do
          default_s_cast_unsafe(__MODULE__, ref, extended_call, context, options)
        end
      end

      if unquote(MapSet.member?(features, :crash_protection)) do

        if (unquote(required.o_call)) do
          @doc """
            Optomized call, assumed call already in ref form and on target server. Simply check if process is alive and forward.
          """
          def o_call(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}, timeout \\ @timeout) do
            default_crash_protection_rs_call({__MODULE__, @base, @worker_lookup_handler, @s_redirect_feature, @log_timeouts}, identifier, call, context, options, timeout)
          end # end s_call!
        end

        if (unquote(required.o_cast)) do
          @doc """
            Optomized call, assumed call already in ref form and on target server. Simply check if process is alive and forward.
          """
          def o_cast(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
            default_crash_protection_rs_cast({__MODULE__, @base, @worker_lookup_handler, @s_redirect_feature, @log_timeouts}, identifier, call, context, options)
          end # end s_call!
        end


        if (unquote(required.rs_call!)) do
          def rs_call!(identifier, call, context, options, timeout) do
            default_crash_protection_rs_call!({__MODULE__, @base, @worker_lookup_handler, @s_redirect_feature, @log_timeouts}, identifier, call, context, options, timeout)
          end
        end

        if (unquote(required.s_call!)) do
          @doc """
            Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
          """
          def s_call!(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}, timeout \\ @timeout) do
            default_crash_protection_s_call!(__MODULE__, identifier, call, context , options, timeout)
          end # end s_call!
        end
        if (unquote(required.rs_cast!)) do
          def rs_cast!(identifier, call, context, options) do
            default_crash_protection_rs_cast!({__MODULE__, @base, @worker_lookup_handler, @s_redirect_feature, @log_timeouts}, identifier, call, context, options)
          end
        end
        if (unquote(required.s_cast!)) do
          @doc """
            Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
          """
          def s_cast!(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
            default_crash_protection_s_cast!(__MODULE__, identifier, call, context, options)
          end # end s_cast!
        end
        if (unquote(required.rs_call)) do
          def rs_call(identifier, call, context, options, timeout) do
            default_crash_protection_rs_call({__MODULE__, @base, @worker_lookup_handler, @s_redirect_feature, @log_timeouts}, identifier, call, context, options, timeout)
          end
        end
        if (unquote(required.s_call)) do
          @doc """
            Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
          """
          def s_call(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}, timeout \\ @timeout) do
            timeout = options[:timeout] || @timeout
            default_crash_protection_s_call(__MODULE__, identifier, call, context, options, timeout)
          end # end s_call!
        end
        if (unquote(required.rs_cast)) do
          def rs_cast(identifier, call, context, options) do
            default_crash_protection_rs_cast({__MODULE__, @base, @worker_lookup_handler, @s_redirect_feature, @log_timeouts}, identifier, call, context, options)
          end
        end

        if (unquote(required.workers!)) do


          def workers!(server, %Noizu.ElixirCore.CallingContext{} = context) do
            @worker_lookup_handler.workers!(server, @worker_state_entity, context, %{})
          end # end s_cast!

          def workers!(server, %Noizu.ElixirCore.CallingContext{} = context, options) do
            @worker_lookup_handler.workers!(server, @worker_state_entity, context, options)
          end # end s_cast!

          def workers!(%Noizu.ElixirCore.CallingContext{} = context) do
            @worker_lookup_handler.workers!(node(), @worker_state_entity, context, %{})
          end # end s_cast!

          def workers!(%Noizu.ElixirCore.CallingContext{} = context, options) do
            @worker_lookup_handler.workers!(node(), @worker_state_entity, context, options)
          end # end s_cast!
        end

        if (unquote(required.s_cast)) do
          @doc """
            Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
          """
          def s_cast(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
            default_crash_protection_s_cast(__MODULE__, identifier, call, context, options)
          end # end s_cast!
        end

      else # no crash_protection
        if (unquote(required.s_call!)) do
          @doc """
            Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
          """
          def s_call!(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
            timeout = options[:timeout] || @timeout
            default_nocrash_protection_s_call!({__MODULE__, @s_redirect_feature}, identifier, call, context, options, timeout)
          end # end s_call!
        end
        if (unquote(required.s_cast!)) do

          @doc """
            Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
          """
          def s_cast!(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{})) do
            default_nocrash_protection_s_cast!({__MODULE__, @s_redirect_feature}, identifier, call, context, options)
          end # end s_cast!
        end
        if (unquote(required.s_call)) do
          @doc """
            Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
          """
          def s_call(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{})) do
            timeout = options[:timeout] || @timeout
            default_nocrash_protection_s_call({__MODULE__, @s_redirect_feature}, identifier, call, context, options, timeout )
          end # end s_call!
        end
        if (unquote(required.s_cast)) do
          @doc """
            Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
          """
          def s_cast(identifier, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), optiosn \\ %{}) do
            default_nocrash_protection_s_cast({__MODULE__, @s_redirect_feature}, identifier, call, context, options)
          end # end s_cast!
        end
      end # end if feature.crash_protection

      if unquote(required.link_forward!) do
        @doc """
          Crash Protection always enabled, for now.
        """
        def link_forward!(%Link{handler: __MODULE__} = link, call, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}) do
          default_link_forward!({__MODULE__, @base, @s_redirect_feature}, link, call, context, options)
        end # end link_forward!
      end # end if required link_forward!


      if unquote(required.record_service_event!) do
        def record_service_event!(event, details, context, options) do
          @server_monitor.record_service_event!(node(), @base, event, details, context, options)
        end
      end

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
