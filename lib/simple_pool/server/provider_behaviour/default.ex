#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Server.ProviderBehaviour.Default do
    alias Noizu.SimplePool.Server.State
    require Logger
    use Amnesia
    #---------------------------------------------------------------------------
    # GenServer Lifecycle
    #---------------------------------------------------------------------------
    def init(server, sup, definition, options, context) do
      #server.enable_server!(node())

      # TODO load real effective
      effective = %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{
        identifier: {node(), server.base()},
        time_stamp: DateTime.utc_now(),
        status: :offline,
        directive: :init,
        definition: definition,
      }

      state = %State{
          pool: sup,
          server: server,
          status_details: :pending,
          extended: %{},
          entity: %{definition: definition, effective: effective, status: :init},
          options: options
        }
      {:ok, state}
    end

    def terminate(reason, %State{} = state) do
      Logger.warn( fn -> state.server.base().banner("Terminate #{inspect state, pretty: true}\nReason: #{inspect reason}") end)
      #state.server.disable_server!(node())
      :ok
    end

    #---------------------------------------------------------------------------
    # Startup: Lazy Loading/Async Load/Immediate Load strategies.
    # Blocking/Lazy Initialization, Loading Strategy.
    #---------------------------------------------------------------------------
    def status(server, context), do: server.internal_call(:status, context)
    def load(server, settings, context), do: server.internal_call({:load, settings}, context)

    def as_cast({:reply, _reply, state}), do: {:noreply, state}
    def as_cast({:noreply, state}), do: {:noreply, state}
    def as_cast({:stop, reason, _reply, state}), do: {:stop, reason, state}
    def as_cast({:stop, reason, state}), do: {:stop, reason, state}
    #---------------------------------------------------------------------------
    # Internal Routing
    #---------------------------------------------------------------------------

    def get_health_check(state, context, options) do
      allocated = Supervisor.count_children(state.server.pool_supervisor())
      events = lifecycle_events(state, MapSet.new([:start, :exit, :terminate, :timeout]), context, options)
      state = update_health_check(state, allocated, events, context, options)

      response = if options[:events] do
        state.entity.effective
          |> put_in([Access.key(:events)], events)
          |> put_in([Access.key(:process)], self())
      else
        state.entity.effective
          |> put_in([Access.key(:process)], self())
      end

      {:reply, response, state}
    end

    def lifecycle_events(state, filter, context, options) do
      events = Noizu.SimplePool.Database.MonitoringFramework.Service.EventTable.read!({state.entity.effective.identifier}) || []
      Enum.reduce(events, [], fn(x, acc) ->
        if MapSet.member?(filter, x.event) do
          acc ++ [x.entity]
        else
          acc
        end
      end)
    end

    def update_health_check(state, allocated, events, context, options) do
      status = state.entity.effective.status
      current_time = options[:current_time] || :os.system_time(:seconds)
      {health_index, l_index, e_index} = health_tuple(state.entity.effective.definition, allocated, events, current_time)
      cond do
        Enum.member?([:online, :degraded, :critical], status) ->
          updated_status = cond do
            e_index > 12.0 -> :critical
            e_index > 6.0 -> :degraded
            l_index > 5.0 -> :degraded
            health_index > 12.0 -> :critical
            health_index > 9.0 -> :degraded
            true -> :online
          end
          state = state
                  |> put_in([Access.key(:entity), :effective, Access.key(:status)], updated_status)
                  |> put_in([Access.key(:entity), :effective, Access.key(:health_index)], health_index)
                  |> put_in([Access.key(:entity), :effective, Access.key(:allocated)], allocated)
        true ->
          state = state
                  |> put_in([Access.key(:entity), :effective, Access.key(:health_index)], health_index)
                  |> put_in([Access.key(:entity), :effective, Access.key(:allocated)], allocated)
      end
    end

    def health_tuple(definition, allocated, events, current_time) do
      t_factor = if (allocated.active > definition.target), do: 1.0, else: 0.0
      s_factor = if (allocated.active > definition.soft_limit), do: 3.0, else: 0.0
      h_factor = if (allocated.active > definition.hard_limit), do: 8.0, else: 0.0
      e_factor = Enum.reduce(events, 0.0, fn(x, acc) ->
        event_time = DateTime.to_unix(x.time_stamp)
        age = current_time - event_time
        if (age) >= 600 do
          weight = :math.pow((age / 600), 2)
          case x.identifier do
            :start -> acc + (1.0 * weight)
            :exit -> acc + (0.75 * weight)
            :terminate -> acc + (1.5 * weight)
            :timeout -> acc + (0.35 * weight)
            _ -> acc
          end
        else
          acc
        end
      end)
      l_factor = t_factor + s_factor + h_factor
      {l_factor + e_factor, l_factor, e_factor}
    end

    def server_kill!(state, context, options) do
        raise "FORCE_KILL"
    end



    #---------------------------------------------------------------------------
    # Internal Routing - internal_call_handler
    #---------------------------------------------------------------------------
    def internal_call_handler({:health_check!, health_check_options}, context, _from, %State{} = state), do: get_health_check(state, context, health_check_options)
    def internal_call_handler({:load, options}, context, _from, %State{} = state), do: load_workers(options, context, state)
    def internal_call_handler(call, context, _from, %State{} = state) do
        Logger.error(fn -> {" #{inspect state.server} unsupported call(#{inspect call})", Noizu.ElixirCore.CallingContext.metadata(context)} end)
      {:reply, {:error, {:unsupported, call}}, state}
    end
    #---------------------------------------------------------------------------
    # Internal Routing - internal_cast_handler
    #---------------------------------------------------------------------------
    def internal_cast_handler({:server_kill!, options}, context, %State{} = state) do
      server_kill!(state, context, options)
    end

    def internal_cast_handler(call, context, %State{} = state) do
      Logger.error(fn -> {" #{inspect state.server} unsupported cast(#{inspect call, pretty: true})", Noizu.ElixirCore.CallingContext.metadata(context)} end)
      {:noreply, state}
    end

    #---------------------------------------------------------------------------
    # Internal Routing - internal_info_handler
    #---------------------------------------------------------------------------
    def internal_info_handler(call, context, %State{} = state) do
        Logger.error(fn -> {" #{inspect state.server} unsupported info(#{inspect call, pretty: true})", Noizu.ElixirCore.CallingContext.metadata(context)} end)

      {:noreply, state}
    end

    #---------------------------------------------------------------------------
    # Internal Implementations
    #---------------------------------------------------------------------------

    #------------------------------------------------
    # worker_add!()
    #------------------------------------------------
    def worker_add!(ref, options, context, state) do
      if Enum.member?(state.options.effective_options.features, :async_load) do
        {:reply, state.server.worker_sup_start(ref, state.pool, context), state}
      else
        case state.server.worker_sup_start(ref, state.pool, context) do
          {:ok, pid} -> GenServer.cast(pid, {:s, {:load, options}, context})
            {:reply, {:ok, pid}, state}
          error -> {:reply, error, state}
        end
      end
    end

    #------------------------------------------------
    # load_workers
    #------------------------------------------------
    def load_workers(options, context, state) do
      if Enum.member?(state.options.effective_options.features, :async_load) do
        Logger.info( fn -> {state.server.base().banner("Load Workers Async"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
        pid = spawn(fn -> load_workers_async(options, context, state) end)
        status = %{state.status| loading: :in_progress, state: :initialization}

        state = state
                |> put_in([Access.key(:entity), :effective, Access.key(:status)], :loading)
                |> put_in([Access.key(:entity), :effective, Access.key(:directive)], :loading)

        state = %State{state| status: status, extended: Map.put(state.extended, :load_process, pid)}
        {:reply, {:ok, :loading}, state}
      else
        if Enum.member?(state.options.effective_options.features, :lazy_load) do
          Logger.info(fn -> {state.server.base().banner("Lazy Load Workers #{inspect state.entity}"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
          # nothing to do,
          state = state
                  |> put_in([Access.key(:entity), :effective, Access.key(:status)], :online)
                  |> put_in([Access.key(:entity), :effective, Access.key(:directive)], :online)

          state = %State{state| status: %{state.status| loading: :complete, state: :ready}}
          {:reply, {:ok, :loaded}, state}
        else
          Logger.info(fn -> {state.server.base().banner("Load Workers"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
          :ok = load_workers_sync(options, context, state)
          state = state
                  |> put_in([Access.key(:entity), :effective, Access.key(:status)], :online)
                  |> put_in([Access.key(:entity), :effective, Access.key(:directive)], :online)

          state = %State{state| status: %{state.status| loading: :complete, state: :ready}}
          {:reply, {:ok, :loaded}, state}
        end
      end
    end

    def load_complete(_source, state, _context) do
      status = %{state.status| loading: :complete, state: :ready}
      state = state
        |> put_in([Access.key(:entity), :effective, Access.key(:status)], :online)
        |> put_in([Access.key(:entity), :effective, Access.key(:directive)], :online)

      state = %State{state| status: status, extended: Map.put(state.extended, :load_process, nil)}
      {:noreply, state}
    end

    #------------------------------------------------
    # load_workers_async
    #------------------------------------------------
    def load_workers_async(options, context, state) do
      Amnesia.Fragment.transaction do
        load_workers_async(state.server.worker_state_entity().worker_refs(options, context, state), options, context, state)
      end
    end
    def load_workers_async(nil, _options, context, state), do: state.server.load_complete({self(), node()}, context, state)
    def load_workers_async(sel, options, context, state) do
      values = Amnesia.Selection.values(sel)
      for value <- values do
        ref = state.server.ref(value)
        worker_add!(ref, options, context, state)
      end
      load_workers_async(Amnesia.Selection.next(sel), options, context, state)
    end

    #------------------------------------------------
    # load_workers_sync
    #------------------------------------------------
    def load_workers_sync(options, context, state) do
      Amnesia.Fragment.transaction do
        load_workers_sync(state.server.worker_state_entity().worker_refs(), options, context, state)
      end
    end
    def load_workers_sync(nil, _options, _context, _state), do: :ok
    def load_workers_sync(sel, options, context, state) do
      values = Amnesia.Selection.values(sel)
      for value <- values do
        ref = state.server.ref(value)
        worker_add!(ref, options, context, state)
      end
      load_workers_sync(Amnesia.Selection.next(sel), options, context, state)
    end
end
