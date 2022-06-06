#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.WorkerBehaviourDefault do
  require Logger

  @telemetry_handler Application.get_env(:noizu_simple_pool, :telemetry_handler, Noizu.SimplePool.Telemetry)

  def verbose(verbose, base) do
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

  def init({_mod, server, base, _worker_state_entity, _inactivity_check, _lazy_load}, {:migrate, ref, initial_state, context}) do
    @telemetry_handler.worker_init_span(base, ref,
      fn ->
        server.worker_lookup_handler().register!(ref, context)
        task = server.worker_lookup_handler().set_node!(ref, context)
        r = Task.yield(task, 500)
        {:ok, %Noizu.SimplePool.Worker.State{extended: %{set_node_task: r || task}, initialized: :delayed_init, worker_ref: ref, inner_state: {:transfer, initial_state}}}
      end, context)
  end

  def init({_mod, server, base, _worker_state_entity, _inactivity_check, _lazy_load}, {ref, context}) do
    @telemetry_handler.worker_init_span(base, ref,
      fn ->
        server.worker_lookup_handler().register!(ref, context)
        task = server.worker_lookup_handler().set_node!(ref, context)
        r = Task.yield(task, 500)
        {:ok, %Noizu.SimplePool.Worker.State{extended: %{set_node_task:  r || task}, initialized: :delayed_init, worker_ref: ref, inner_state: :start}}
      end, context)
  end

  def delayed_init({mod, _server, base, worker_state_entity, inactivity_check, lazy_load}, state, context) do
    ref = state.worker_ref
    ustate = case state.inner_state do
      # @TODO - investigate strategies for avoiding keeping full state in child def. Aka put into state that accepts a transfer/reads a transfer form a table, etc.
      {:transfer, {:state, initial_state, :time, time}} ->
        cut_off = :os.system_time(:second) - 60*15
        if time < cut_off do
          if (mod.verbose()) do
            Logger.info(fn -> {base.banner("INIT/1.stale_transfer#{__MODULE__} (#{inspect ref }"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
          end
          #PRI-0 - disabled until rate limit available - spawn fn -> server.worker_lookup_handler().record_event!(ref, :start, :normal, context, %{}) end
          {initialized, inner_state} = if lazy_load do
            case worker_state_entity.load(ref, context) do
              nil -> {false, nil}
              inner_state -> {true, inner_state}
            end
          else
            {false, nil}
          end
          %Noizu.SimplePool.Worker.State{initialized: initialized, worker_ref: ref, inner_state: inner_state}
        else
          if (mod.verbose()) do
            Logger.info(fn -> {base.banner("INIT/1.transfer #{__MODULE__} (#{inspect ref }"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
          end
          #PRI-0 - disabled until rate limit available - spawn fn -> server.worker_lookup_handler().record_event!(ref, :start, :migrate, context, %{}) end
          {initialized, inner_state} = worker_state_entity.transfer(ref, initial_state.inner_state, context)
          %Noizu.SimplePool.Worker.State{initial_state| initialized: initialized, worker_ref: ref, inner_state: inner_state}
        end

      {:transfer, initial_state} ->
        if (mod.verbose()) do
          Logger.info(fn -> {base.banner("INIT/1.transfer #{__MODULE__} (#{inspect ref }"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
        end
        #PRI-0 - disabled until rate limit available - spawn fn -> server.worker_lookup_handler().record_event!(ref, :start, :migrate, context, %{}) end
        {initialized, inner_state} = worker_state_entity.transfer(ref, initial_state.inner_state, context)
          %Noizu.SimplePool.Worker.State{initial_state| initialized: initialized, worker_ref: ref, inner_state: inner_state}
      :start ->
        if (mod.verbose()) do
          Logger.info(fn -> {base.banner("INIT/1 #{__MODULE__} (#{inspect ref }"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
        end
        #PRI-0 - disabled until rate limit available - spawn fn -> server.worker_lookup_handler().record_event!(ref, :start, :normal, context, %{}) end
        {initialized, inner_state} = if lazy_load do
          case worker_state_entity.load(ref, context) do
            nil -> {false, nil}
            inner_state -> {true, inner_state}
          end
        else
          {false, nil}
        end
        %Noizu.SimplePool.Worker.State{initialized: initialized, worker_ref: ref, inner_state: inner_state}
    end



    if inactivity_check do
      ustate = %Noizu.SimplePool.Worker.State{ustate| last_activity: :os.system_time(:seconds)}
      ustate = mod.schedule_inactivity_check(nil, ustate)
      ustate
    else
      ustate
    end
  end

  def schedule_migrate_shutdown(migrate_shutdown_interval_ms, context, state) do
    {:ok, mt_ref} = :timer.send_after(migrate_shutdown_interval_ms, self(), {:i, {:migrate_shutdown, state.worker_ref}, context})
    put_in(state, [Access.key(:extended), :mt_ref], mt_ref)
  end

  def clear_migrate_shutdown(state) do
    case Map.get(state.extended, :mt_ref) do
      nil -> state
      mt_ref ->
        :timer.cancel(mt_ref)
        put_in(state, [Access.key(:extended), :mt_ref], nil)
    end
  end

  def handle_migrate_shutdown(mod, server, worker_state_entity, inactivity_check, {:i, {:migrate_shutdown, ref}, context}, %Noizu.SimplePool.Worker.State{migrating: true} = state) do
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

  def handle_migrate_shutdown(_mod, _server, _worker_state_entity, _inactivity_check, {:i, {:migrate_shutdown, _ref}, context}, %Noizu.SimplePool.Worker.State{migrating: false} = state) do
    Logger.error(fn -> {"#{__MODULE__}.migrate_shutdown called when not in migrating state" , Noizu.ElixirCore.CallingContext.metadata(context)} end)
    {:noreply, state}
  end # end handle_info/:activity_check


  def schedule_inactivity_check(check_interval_ms, context, state) do
    {:ok, t_ref} = :timer.send_after(check_interval_ms, self(), {:i, {:activity_check, state.worker_ref}, context})
    put_in(state, [Access.key(:extended), :t_ref], t_ref)
  end

  def clear_inactivity_check(state) do
    case Map.get(state.extended, :t_ref) do
      nil -> state
      t_ref ->
        :timer.cancel(t_ref)
        put_in(state, [Access.key(:extended), :t_ref], nil)
    end
  end

  def handle_activity_check(mod, _server, _worker_state_entity, kill_interval_s, {:i, {:activity_check, ref}, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state ) do
    if ref == state.worker_ref do
      if ((state.last_activity == nil) || ((state.last_activity + kill_interval_s) < :os.system_time(:seconds))) do
        #server.worker_remove!(ref, [force: true], context)
        {:stop, {:shutdown, :inactive}, mod.clear_inactivity_check(state)}
      else
        {:noreply, mod.schedule_inactivity_check(context, state)}
      end
    else
      {:noreply, state}
    end
  end

  def handle_activity_check(mod, _server, worker_state_entity, kill_interval_s, {:i, {:activity_check, ref}, context}, %Noizu.SimplePool.Worker.State{initialized: true} = state ) do
    if ref == state.worker_ref do
      if ((state.last_activity == nil) || ((state.last_activity + kill_interval_s) < :os.system_time(:seconds))) do
        case worker_state_entity.shutdown(state, [], context, nil) do
          {:ok, state} ->
            #server.worker_remove!(state.worker_ref, [force: true], context)
            {:stop, {:shutdown, :inactive}, mod.clear_inactivity_check(state)}
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

  def handle_cast_load(worker_state_entity, inactivity_check, {:s, {:load, options}, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case worker_state_entity.load(state.worker_ref, context, options) do
      nil -> {:noreply, state}
      inner_state ->
        if inactivity_check do
          {:noreply, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        else
          {:noreply, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}}
        end
    end
  end


  def handle_call_load(worker_state_entity, inactivity_check, {:s, {:load, options}, context}, _from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case worker_state_entity.load(state.worker_ref, context, options) do
      nil -> {:reply, :not_found, state}
      inner_state ->
        if inactivity_check do
          {:reply, inner_state, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        else
          {:reply, inner_state, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}}
        end
    end
  end



  def handle_cast_migrate(_mod, server, _worker_state_entity, _migrate_shutdown, {:s, {:migrate!, ref, rebase, options}, context}, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
    cond do
      (rebase == node() && ref == state.worker_ref) -> {:noreply, state}
      true ->
        case :rpc.call(rebase, server, :accept_transfer!, [ref, state, context, options], options[:timeout] || 60_000) do
          {:ack, _pid} -> {:stop, {:shutdown, :migrate}, state}
          _r -> {:noreply, state}
        end
    end
  end

  def handle_call_migrate(_mod, server, _worker_state_entity, _migrate_shutdown, {:s, {:migrate!, ref, rebase, options}, context}, _from,  %Noizu.SimplePool.Worker.State{initialized: true} = state) do
    cond do
      (rebase == node() && ref == state.worker_ref) -> {:reply, {:ack, self()}, state}
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
  def handle_call_lazy_load(mod, worker_state_entity, {:s, _inner, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case worker_state_entity.load(state.worker_ref, context) do
      nil -> {:reply, :initilization_failed, state}
      inner_state ->
        mod.handle_call(call, from, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
    end
  end # end handle_call

  def handle_cast_lazy_load(mod, worker_state_entity, {:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case worker_state_entity.load(state.worker_ref, context) do
      nil -> {:noreply, state}
      inner_state ->
        mod.handle_cast(call, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
    end
  end # end handle_call

  def handle_info_lazy_load(mod, worker_state_entity, {:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case worker_state_entity.load(state.worker_ref, context) do
      nil -> {:noreply, state}
      inner_state ->
        mod.handle_info(call, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
    end
  end # end handle_call

  def handle_call_shutdown(mod, worker_state_entity, {:s, {:shutdown, options} = _inner_call, context} = _call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: _inner_state} = state) do
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
  def handle_cast_forwarding(worker_state_entity, inactivity_check, {:s, inner_call, context} = _call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
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

  def handle_call_forwarding(worker_state_entity, inactivity_check, {:s, inner_call, context} = _call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
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

end
