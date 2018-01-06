#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.WorkerBehaviour do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList
  require Logger

  @methods ([:verbose, :options, :option_settings, :start_link, :terminate, :init, :schedule_migrate_shutdown, :clear_migrate_shutdown, :schedule_inactivity_check, :clear_inactivity_check, :save!, :fetch, :reload!])
  @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])
  @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])

  @default_check_interval_ms (1000 * 60 * 5)
  @default_kill_interval_ms (1000 * 60 * 15)

  @callback option_settings() :: Noizu.SimplePool.OptionSettings.t

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: :auto},
        worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
        check_interval_ms: %OptionValue{option: :check_interval_ms, default: Application.get_env(:noizu_simple_pool, :default_inactivity_check_interval_ms, @default_check_interval_ms)},
        kill_interval_ms: %OptionValue{option: :kill_interval_ms, default: Application.get_env(:noizu_simple_pool, :default_inactivity_kill_interval_ms, @default_kill_interval_ms)},
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

  def default_init({mod, server, base, worker_state_entity, inactivity_check, _lazy_load}, {:migrate, ref, initial_state, context}) do
    if (mod.verbose()) do
      Logger.info(fn -> {base.banner("INIT/1.transfer #{__MODULE__} (#{inspect ref }"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
    end
    server.worker_lookup_handler().register!(ref, context)
    server.worker_lookup_handler().record_event!(ref, :start, :migrate, context, %{})
    {initialized, inner_state} = worker_state_entity.transfer(ref, initial_state.inner_state, context)


    if inactivity_check do
      state = %Noizu.SimplePool.Worker.State{initial_state| initialized: initialized, worker_ref: ref, inner_state: inner_state, last_activity: :os.system_time(:seconds)}
      state = mod.schedule_inactivity_check(nil, state)
      {:ok, state}
    else
      {:ok, %Noizu.SimplePool.Worker.State{initial_state| initialized: initialized, worker_ref: ref, inner_state: inner_state}}
    end
  end

  def default_init({mod, server, base, worker_state_entity, inactivity_check, lazy_load}, {ref, context}) do
    if (mod.verbose()) do
      Logger.info(fn -> {base.banner("INIT/1 #{__MODULE__} (#{inspect ref }"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
    end
    Noizu.ElixirCore.CallingContext.meta_update(context)
    server.worker_lookup_handler().register!(ref, context)
    server.worker_lookup_handler().record_event!(ref, :start, :normal, context, %{})
    {initialized, inner_state} = if lazy_load do
      case worker_state_entity.load(ref, context) do
        nil -> {false, nil}
        inner_state -> {true, inner_state}
      end
    else
      {false, nil}
    end

    if inactivity_check do
      state = %Noizu.SimplePool.Worker.State{initialized: initialized, worker_ref: ref, inner_state: inner_state, last_activity: :os.system_time(:seconds)}
      state = mod.schedule_inactivity_check(nil, state)
      {:ok, state}
    else
      {:ok, %Noizu.SimplePool.Worker.State{initialized: initialized, worker_ref: ref, inner_state: inner_state}}
    end
  end

  def default_schedule_migrate_shutdown(migrate_shutdown_interval_ms, context, state) do
    {:ok, mt_ref} = :timer.send_after(migrate_shutdown_interval_ms, self(), {:i, {:migrate_shutdown, state.worker_ref}, context})
    put_in(state, [Access.key(:extended), :mt_ref], mt_ref)
  end

  def default_clear_migrate_shutdown(state) do
    case Map.get(state.extended, :mt_ref) do
      nil -> state
      mt_ref ->
        :timer.cancel(mt_ref)
        put_in(state, [Access.key(:extended), :mt_ref], nil)
    end
  end

  def default_handle_migrate_shutdown(mod, server, worker_state_entity, inactivity_check, {:i, {:migrate_shutdown, ref}, context}, %Noizu.SimplePool.Worker.State{migrating: true} = state) do
    if ref == state.worker_ref do
      state = mod.clear_migrate_shutdown(state)
      state = if inactivity_check, do: mod.clear_inactivity_check(state), else:  state

      if state.initialized do
        case worker_state_entity.migrate_shutdown(state, context) do
          {:ok, state} ->
            server.worker_terminate!(ref, nil, context)
            {:noreply, state}
          {:wait, state} ->
            {:noreply, mod.schedule_migrate_shutdown(context, state)}
        end
      else
        server.worker_terminate!(ref, nil, context)
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end # end handle_info/:activity_check

  def default_handle_migrate_shutdown(_mod, _server, _worker_state_entity, _inactivity_check, {:i, {:migrate_shutdown, _ref}, _context}, %Noizu.SimplePool.Worker.State{migrating: false} = state) do
    Logger.error(fn -> "#{__MODULE__}.migrate_shutdown called when not in migrating state"  end)
    {:noreply, state}
  end # end handle_info/:activity_check


  def default_schedule_inactivity_check(check_interval_ms, context, state) do
    {:ok, t_ref} = :timer.send_after(check_interval_ms, self(), {:i, {:activity_check, state.worker_ref}, context})
    put_in(state, [Access.key(:extended), :t_ref], t_ref)
  end

  def default_clear_inactivity_check(state) do
    case Map.get(state.extended, :t_ref) do
      nil -> state
      t_ref ->
        :timer.cancel(t_ref)
        put_in(state, [Access.key(:extended), :t_ref], nil)
    end
  end

  def default_handle_activity_check(mod, server, _worker_state_entity, kill_interval_s, {:i, {:activity_check, ref}, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state ) do
    if ref == state.worker_ref do
      if ((state.last_activity == nil) || ((state.last_activity + kill_interval_s) < :os.system_time(:seconds))) do
        server.worker_remove!(ref, [force: true], context)
        {:noreply, mod.clear_inactivity_check(state)}
      else
        {:noreply, mod.schedule_inactivity_check(context, state)}
      end
    else
      {:noreply, state}
    end
  end

  def default_handle_activity_check(mod, server, worker_state_entity, kill_interval_s, {:i, {:activity_check, ref}, context}, %Noizu.SimplePool.Worker.State{initialized: true} = state ) do
    if ref == state.worker_ref do
      if ((state.last_activity == nil) || ((state.last_activity + kill_interval_s) < :os.system_time(:seconds))) do
        case worker_state_entity.shutdown(state, [], context, nil) do
          {:ok, state} ->
            server.worker_remove!(state.worker_ref, [force: true], context)
            {:noreply, state}
          {:wait, state} ->
            # @TODO force termination conditions needed.
            {:noreply, mod.schedule_inactivity_check(context, state)}
        end
      else
        {:noreply, mod.schedule_inactivity_check(context, state)}
      end
    else
      {:noreply, state}
    end
  end

  def default_handle_cast_load(worker_state_entity, inactivity_check, {:s, {:load, options}, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case worker_state_entity.load(state.worker_ref, options, context) do
      nil -> {:noreply, state}
      inner_state ->
        if inactivity_check do
          {:noreply, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        else
          {:noreply, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}}
        end
    end
  end


  def default_handle_call_load(worker_state_entity, inactivity_check, {:s, {:load, options}, context}, _from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case worker_state_entity.load(state.worker_ref, options, context) do
      nil -> {:reply, :not_found, state}
      inner_state ->
        if inactivity_check do
          {:reply, inner_state, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        else
          {:reply, inner_state, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}}
        end
    end
  end



  def default_handle_cast_migrate(mod, server, worker_state_entity, migrate_shutdown, {:s, {:migrate!, ref, rebase, options}, context}, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
    cond do
      (rebase == node() && ref == state.worker_ref) -> {:noreply, state}
      true ->
        case :rpc.call(rebase, server, :accept_transfer!, [ref, state, context, options], options[:timeout] || 60_000) do
          {:ack, pid} -> {:noreply, state}
          r -> {:noreply, state}
        end
    end
  end

  def default_handle_call_migrate(mod, server, worker_state_entity, migrate_shutdown, {:s, {:migrate!, ref, rebase, options}, context}, _from,  %Noizu.SimplePool.Worker.State{initialized: true} = state) do
    cond do
      (rebase == node() && ref == state.worker_ref) -> {:reply, {:ok, self()}, state}
      true ->
        case :rpc.call(rebase, server, :accept_transfer!, [ref, state, context, options], options[:timeout] || 60_000) do
          {:ack, pid} -> {:stop, {:shutdown, :migrate}, {:ack, pid}, state}
          r ->  {:reply, {:error, r}, state}
        end
    end
  end

  #-------------------------------------------------------------------------
  # Lazy Load Handling Feature Section
  #-------------------------------------------------------------------------
  def default_handle_call_lazy_load(mod, worker_state_entity, {:s, _inner, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case worker_state_entity.load(state.worker_ref, context) do
      nil -> {:reply, :initilization_failed, state}
      inner_state ->
        mod.handle_call(call, from, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
    end
  end # end handle_call


  def default_handle_cast_lazy_load(mod, worker_state_entity, {:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case worker_state_entity.load(state.worker_ref, context) do
      nil -> {:noreply, state}
      inner_state ->
        mod.handle_cast(call, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
    end
  end # end handle_call

  def default_handle_info_lazy_load(mod, worker_state_entity, {:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case worker_state_entity.load(state.worker_ref, context) do
      nil -> {:noreply, state}
      inner_state ->
        mod.handle_info(call, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
    end
  end # end handle_call

  def default_handle_call_shutdown(mod, worker_state_entity, {:s, {:shutdown, options} = _inner_call, context} = _call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: _inner_state} = state) do
    {reply, state} = worker_state_entity.shutdown(state, options, context, from)
    case reply do
      :ok ->
        {:reply, reply, mod.clear_inactivity_check(state)}
      :wait ->
        {:reply, reply, state}
    end
  end

  #-------------------------------------------------------------------------
  # Call Forwarding Feature Section
  #-------------------------------------------------------------------------
  def default_handle_cast_forwarding(worker_state_entity, inactivity_check, {:s, inner_call, context} = _call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
    case worker_state_entity.call_forwarding(inner_call, context, inner_state) do
      {:stop, reason, inner_state} ->
        if inactivity_check do
          {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        else
          {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        end
      {:noreply, inner_state} ->
        if inactivity_check do
          {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        else
          {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        end
      {:noreply, inner_state, hibernate} ->
        if inactivity_check do
          {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}, hibernate}
        else
          {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}, hibernate}
        end

    end
  end

  def default_handle_call_forwarding(worker_state_entity, inactivity_check, {:s, inner_call, context} = _call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
    case worker_state_entity.call_forwarding(inner_call, context, from, inner_state) do
      {:stop, reason, inner_state} ->
        if inactivity_check do
          {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        else
          {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        end
      {:stop, reason, response, inner_state} ->
        if inactivity_check do
          {:stop, reason, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        else
          {:stop, reason, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        end
      {:reply, response, inner_state} ->
        if inactivity_check do
          {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        else
          {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        end
      {:reply, response, inner_state, hibernate} ->
        if inactivity_check do
          {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}, hibernate}
        else
          {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}, hibernate}
        end
      {:noreply, inner_state} ->
        if inactivity_check do
          {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        else
          {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        end
      {:noreply, inner_state, hibernate} ->
        if inactivity_check do
          {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}, hibernate}
        else
          {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}, hibernate}
        end
    end
  end

  defmacro __using__(options) do
    option_settings = prepare_options(options)
    options = option_settings.effective_options
    required = options.required
    features = MapSet.new(options.features)
    verbose = options.verbose

    quote do
      import unquote(__MODULE__)
      require Logger
      @behaviour Noizu.SimplePool.WorkerBehaviour
      use GenServer
      @base (Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat)
      @server (Module.concat([@base, "Server"]))
      @worker_state_entity (Noizu.SimplePool.Behaviour.expand_worker_state_entity(@base, unquote(options.worker_state_entity)))
      @check_interval_ms (unquote(options.check_interval_ms))
      @kill_interval_s (unquote(options.kill_interval_ms)/1000)
      @migrate_shutdown_interval_ms (5_000)
      @migrate_shutdown unquote(MapSet.member?(features, :migrate_shutdown))
      @inactivity_check unquote(MapSet.member?(features, :inactivity_check))
      @lazy_load unquote(MapSet.member?(features, :lazy_load))
      @base_verbose (unquote(verbose))


      @option_settings unquote(Macro.escape(option_settings))
      @options unquote(Macro.escape(options))

      if (unquote(required.verbose)) do
        def verbose(), do: default_verbose(@base_verbose, @base)
      end

      if (unquote(required.option_settings)) do
        def option_settings(), do: @option_settings
      end

      if (unquote(required.options)) do
        def options(), do: @options
      end

      # @start_link
      if (unquote(required.start_link)) do
        def start_link(args, context) do
          if (verbose()) do
            Logger.info(fn -> @base.banner("START_LINK/1 #{__MODULE__} (#{inspect args})") end)
          end
          GenServer.start_link(__MODULE__, {args, context})
        end

        def start_link(ref, args, context) do
          if (verbose()) do
            Logger.info(fn -> @base.banner("START_LINK/2.migrate #{__MODULE__} (#{inspect args})") end)
          end
          GenServer.start_link(__MODULE__, {:migrate, ref, args, context})
        end
      end # end start_link

      # @terminate
      if (unquote(required.terminate)) do
        def terminate(reason, state) do
          if (verbose()) do
            Logger.info(fn -> @base.banner("TERMINATE #{__MODULE__} (#{inspect state.worker_ref}\n Reason: #{inspect reason}") end)
          end
          @worker_state_entity.terminate_hook(reason, clear_inactivity_check(state))
          #@server.worker_lookup_handler().record_event!(state.worker_ref, :terminate, reason, Noizu.ElixirCore.CallingContext.system(%{}), %{})
        end
      end # end start_link

      @doc """
      @init
      @TODO use defmacro to strip out unnecessary compile time conditionals
      """
      if (unquote(required.init)) do
        def init(arg) do
          default_init({__MODULE__, @server, @base, @worker_state_entity, @inactivity_check, @lazy_load}, arg)
        end
      end # end init

      # @s_redirect
      if unquote(MapSet.member?(features, :s_redirect)) || unquote(MapSet.member?(features, :s_redirect_handle)) do
        def handle_call({_type, {@server, _ref, _timeout}, call}, from, state), do: handle_call(call, from, state)
        def handle_cast({_type, {@server, _ref}, call}, state), do: handle_cast(call, state)

        def handle_cast({:s_cast, {call_server, ref}, {:s, _inner, context} = call}, state) do
          Logger.info(fn -> "Dispatch Error: #{inspect call} ->  #{__MODULE__} #{inspect state}" end)
          {:noreply, state}
        end # end handle_cast/:s_cast

        def handle_cast({:s_cast!, {call_server, ref}, {:s, _inner, context} = call}, state) do
          Logger.info(fn -> "Dispatch Error: #{inspect call} ->  #{__MODULE__} #{inspect state}" end)
          {:noreply, state}
        end # end handle_cast/:s_cast!

        def handle_call({:s_call, {call_server, ref, timeout}, {:s, _inner, context} = call}, from, state) do
          Logger.info(fn -> "Dispatch Error: #{inspect call} ->  #{__MODULE__} #{inspect state}" end)
          {:reply, :s_retry, state}
        end # end handle_call/:s_call

        def handle_call({:s_call!, {call_server, ref, timeout}, {:s, _inner, context}} = call, from, state) do
          Logger.info(fn -> "Dispatch Error: #{inspect call} ->  #{__MODULE__} #{inspect state}" end)
          {:reply, :s_retry, state}
        end # end handle_call/:s_call!
      end # if feature.s_redirect

      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------
      if (unquote(required.schedule_migrate_shutdown)) do
        def schedule_migrate_shutdown(context, state) do
          default_schedule_migrate_shutdown(@migrate_shutdown_interval_ms, context, state)
        end
      end
      if (unquote(required.clear_migrate_shutdown)) do
        def clear_migrate_shutdown(state) do
          default_clear_migrate_shutdown(state)
        end
      end
      def handle_info({:i, {:migrate_shutdown, ref}, context} = call, %Noizu.SimplePool.Worker.State{migrating: status} = state) do
        default_handle_migrate_shutdown(__MODULE__, @server, @worker_state_entity, @inactivity_check, call, state)
      end # end handle_info/:activity_check

      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------

      if (unquote(required.schedule_inactivity_check)) do
        def schedule_inactivity_check(context, state) do
          default_schedule_inactivity_check(@check_interval_ms, context, state)
        end
      end
      if (unquote(required.clear_inactivity_check)) do
        def clear_inactivity_check(state) do
          default_clear_inactivity_check(state)
        end
      end

      def handle_info({:i, {:activity_check, ref}, context} = call, %Noizu.SimplePool.Worker.State{initialized: _i} = state) do
        default_handle_activity_check(__MODULE__, @server, @worker_state_entity, @kill_interval_s, call, state)
      end # end handle_info/:activity_check

      #-------------------------------------------------------------------------
      # Special Section for handlers that require full context
      # @TODO change call_Forwarding to allow passing back and forth full state.
      #-------------------------------------------------------------------------
      if (unquote(required.save!)) do
        def handle_call({:s, {:save!, options}, context} = call, _from, %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.save!(state, options, context)
        end

        def handle_cast({:s, {:save!, options}, context} = call, %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.save!(state, options, context) |> Noizu.SimplePool.InnerStateBehaviour.as_cast()
        end

        def handle_info({:s, {:save!, options}, context} = call, %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.save!(state, options, context) |> Noizu.SimplePool.InnerStateBehaviour.as_cast()
        end
      end

      if (unquote(required.fetch)) do
        def handle_call({:s, {:fetch, :state}, context} = call, _from,  %Noizu.SimplePool.Worker.State{} = state) do
          {:reply, state, state}
        end

        def handle_call({:s, {:fetch, :process}, context} = call, _from,  %Noizu.SimplePool.Worker.State{} = state) do
          {:reply, {@worker_state_entity.ref(state.inner_state), self(), node()}, state}
        end
      end

      if (unquote(required.reload!)) do
        def handle_call({:s, {:reload!, options}, context} = call, _from,  %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.reload!(state, options, context)
        end

        def handle_cast({:s, {:reload!, options}, context} = call, %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.reload!(state, options, context) |> Noizu.SimplePool.InnerStateBehaviour.as_cast()
        end

        def handle_info({:s, {:reload!, options}, context} = call, %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.reload!(state, options, context) |> Noizu.SimplePool.InnerStateBehaviour.as_cast()
        end
      end

      #-------------------------------------------------------------------------
      # Load handler, placed before lazy load to avoid resending load commands
      #-------------------------------------------------------------------------
      def handle_cast({:s, {:load, options}, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
        default_handle_cast_load(@worker_state_entity, @inactivity_check, call, state)
      end

      def handle_info({:s, {:load, options}, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
        handle_cast({:s, {:load, options}, context}, state)
      end

      def handle_call({:s, {:load, options}, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
        default_handle_call_load(@worker_state_entity, @inactivity_check, call, from, state)
      end

      def handle_cast({:s, {:migrate!, ref, rebase, options}, context} = call, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
        default_handle_cast_migrate(__MODULE__, @server, @worker_state_entity, @migrate_shutdown, call, state)
      end

      def handle_info({:s, {:migrate!, ref, rebase, options}, context}, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
        handle_cast({:s, {:migrate!, ref, rebase, options}, context}, state)
      end

      def handle_call({:s, {:migrate!, ref, rebase, options}, context}  = call, from, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
        default_handle_call_migrate(__MODULE__, @server, @worker_state_entity, @migrate_shutdown, call, from, state)
      end

      #-------------------------------------------------------------------------
      # Lazy Load Handling Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :lazy_load)) do
        def handle_call({:s, _inner, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          default_handle_call_lazy_load(__MODULE__, @worker_state_entity, call, from, state)
        end # end handle_call

        def handle_cast({:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          default_handle_cast_lazy_load(__MODULE__, @worker_state_entity, call, state)
        end # end handle_cast

        def handle_info({:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          default_handle_info_lazy_load(__MODULE__, @worker_state_entity, call, state)
        end # end handle_info
      end # end lazy_load feature block

      # Capture shutdown with full state  to allow for timer clearing, etc.
      def handle_call({:s, {:shutdown, options} = _inner_call, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: _inner_state} = state) do
        default_handle_call_shutdown(__MODULE__, @worker_state_entity, call, from, state)
      end

      #-------------------------------------------------------------------------
      # Call Forwarding Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :call_forwarding)) do
        def handle_info({:s, inner_call, context} = call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          default_handle_cast_forwarding(@worker_state_entity, @inactivity_check, call, state)
        end

        def handle_cast({:s, inner_call, context} = call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          default_handle_cast_forwarding(@worker_state_entity, @inactivity_check, call, state)
        end

        def handle_call({:s, inner_call, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          default_handle_call_forwarding(@worker_state_entity, @inactivity_check, call, from, state)
        end
      end # end call forwarding feature section
      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
      def handle_call(uncaught, _from, state) do
        Logger.info(fn -> "Uncaught handle_call to #{__MODULE__} . . . #{inspect uncaught}"  end)
        {:noreply, state}
      end

      def handle_cast(uncaught, state) do
        Logger.info(fn -> "Uncaught handle_cast to #{__MODULE__} . . . #{inspect uncaught}"  end)
        {:noreply, state}
      end

      def handle_info(uncaught, state) do
        Logger.info(fn -> "Uncaught handle_info to #{__MODULE__} . . . #{inspect uncaught}"  end)
        {:noreply, state}
      end
    end # end quote
  end # end __before_compile__
end
