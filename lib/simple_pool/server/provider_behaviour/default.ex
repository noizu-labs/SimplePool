#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Server.ProviderBehaviour.Default do
    alias Noizu.SimplePool.Server.State
    alias Noizu.SimplePool.Server.EnvironmentDetails
    require Logger
    use Amnesia
    #---------------------------------------------------------------------------
    # GenServer Lifecycle
    #---------------------------------------------------------------------------
    def init(server, sup, definition, context, options) do
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
          worker_supervisor: sup,
          service: server,
          status_details: :pending,
          extended: %{},
          environment_details: %EnvironmentDetails{definition: definition, effective: effective, status: :init},
          options: options
        }

      server.record_service_event!(:start, %{definition: definition, options: options}, context, %{})
      {:ok, state}
    end

    def terminate(server, reason, %State{} = this, context, options) do
      server.record_service_event!(:terminate, %{reason: reason}, context, options)
      Logger.warn( fn -> server.base().banner("Terminate #{inspect this, pretty: true}\nReason: #{inspect reason}") end)
      #this.server.disable_server!(node())
      :ok
    end

    #---------------------------------------------------------------------------
    # Startup: Lazy Loading/Async Load/Immediate Load strategies.
    # Blocking/Lazy Initialization, Loading Strategy.
    #---------------------------------------------------------------------------
    def status(server, context), do: server.internal_call(:status, context)
    def load(server, context, options), do: server.internal_system_call({:load, options}, context, %{})

    def as_cast({:reply, _reply, state}), do: {:noreply, state}
    def as_cast({:noreply, state}), do: {:noreply, state}
    def as_cast({:stop, reason, _reply, state}), do: {:stop, reason, state}
    def as_cast({:stop, reason, state}), do: {:stop, reason, state}
    #---------------------------------------------------------------------------
    # Internal Routing
    #---------------------------------------------------------------------------

    def get_health_check(this, context, options) do
      allocated = Supervisor.count_children(this.service.pool_supervisor())
      events = lifecycle_events(this, MapSet.new([:start, :exit, :terminate, :timeout]), context, options)
      this = update_health_check(this, allocated, events, context, options)

      response = if options[:events] do
        this.environment_details.effective
          |> put_in([Access.key(:events)], events)
          |> put_in([Access.key(:process)], self())
      else
        this.environment_details.effective
          |> put_in([Access.key(:process)], self())
      end

      {:reply, response, this}
    end

    def lifecycle_events(this, filter, _context, _options) do
      (Noizu.SimplePool.Database.MonitoringFramework.Service.EventTable.read!(this.environment_details.effective.identifier) || [])
      |>  Enum.reduce([], fn(x, acc) ->
        if MapSet.member?(filter, x.event) do
          acc ++ [x.entity]
        else
          acc
        end
      end)
    end

    def update_health_check(this, allocated, events, _context, options) do
      status = this.environment_details.effective.status
      current_time = options[:current_time] || :os.system_time(:seconds)
      {health_index, l_index, e_index} = health_tuple(this.environment_details.effective.definition, allocated, events, current_time)
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
          this
          |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], updated_status)
          |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:health_index)], health_index)
          |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:allocated)], allocated)
        true ->
          this
          |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:health_index)], health_index)
          |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:allocated)], allocated)
      end
    end

    def health_tuple(definition, allocated, events, current_time) do
      t_factor = if (allocated.active > definition.target), do: 1.0, else: 0.0
      s_factor = if (allocated.active > definition.soft_limit), do: 3.0, else: 0.0
      h_factor = if (allocated.active > definition.hard_limit), do: 8.0, else: 0.0
      e_factor = Enum.reduce(events, 0.0, fn(x, acc) ->
        event_time = DateTime.to_unix(x.time_stamp)
        age = current_time - event_time
        if (age < 600 && age >= 0) do
          weight = :math.pow(( (600-age) / 600), 2)
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

    def server_kill!(_this, _context, _options) do
        raise "FORCE_KILL"
    end

    def lock!(this, _context, _options) do
      # TODO obtain lock, etc. - record event?
      this = this
        |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:directive)], :maintenance)
        |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], :locked)
      {:reply, {:ack, this.environment_details.effective}, this}
    end

    def release!(this, context, options) do
      # TODO obtain lock, etc. - record event?
      this = this
              |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:directive)], :active)
              |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], :online)
      {_, e, this} = get_health_check(this, context, options)
      {:reply, {:ack, e}, this}
    end

    #---------------------------------------------------------------------------
    # Internal Routing - internal_call_handler
    #---------------------------------------------------------------------------
    def internal_call_handler({:lock!, options}, context, _from, %State{} = this), do: lock!(this, context, options)
    def internal_call_handler({:release!, options}, context, _from, %State{} = this), do: release!(this, context, options)
    def internal_call_handler({:health_check!, health_check_options}, context, _from, %State{} = this), do: get_health_check(this, context, health_check_options)
    def internal_call_handler({:load, options}, context, _from, %State{} = this), do: load_workers(this, context, options)
    def internal_call_handler(call, context, _from, %State{} = this) do
        Logger.error(fn -> {"#{__MODULE__} #{inspect this.service} unsupported call(#{inspect call})", Noizu.ElixirCore.CallingContext.metadata(context)} end)
      {:reply, {:error, {:unsupported, call}}, this}
    end
    #---------------------------------------------------------------------------
    # Internal Routing - internal_cast_handler
    #---------------------------------------------------------------------------
    def internal_cast_handler({:server_kill!, options}, context, %State{} = this) do
      server_kill!(this, context, options)
    end

    def internal_cast_handler(call, context, %State{} = this) do
      Logger.error(fn -> {"#{__MODULE__} #{inspect this.service} unsupported cast(#{inspect call, pretty: true})", Noizu.ElixirCore.CallingContext.metadata(context)} end)
      {:noreply, this}
    end

    #---------------------------------------------------------------------------
    # Internal Routing - internal_info_handler
    #---------------------------------------------------------------------------
    def internal_info_handler(call, context, %State{} = this) do
        Logger.error(fn -> {"#{__MODULE__} #{inspect this.service} unsupported info(#{inspect call, pretty: true})", Noizu.ElixirCore.CallingContext.metadata(context)} end)

      {:noreply, this}
    end

    #---------------------------------------------------------------------------
    # Internal Implementations
    #---------------------------------------------------------------------------

    #------------------------------------------------
    # worker_add!()
    #------------------------------------------------
    def worker_add!(this, ref, context, options) do
      if Enum.member?(this.options.effective_options.features, :async_load) do
        {:reply, this.service.worker_sup_start(ref, context), this}
      else
        case this.service.worker_sup_start(ref, this.worker_supervisor, context) do
          {:ok, pid} -> GenServer.cast(pid, {:s, {:load, options}, context})
            {:reply, {:ok, pid}, this}
          error -> {:reply, error, this}
        end
      end
    end

    #------------------------------------------------
    # load_workers
    #------------------------------------------------
    def load_workers(this, context, options) do
      if Enum.member?(this.options.effective_options.features, :async_load) do
        Logger.info( fn -> {this.service.base().banner("Load Workers Async"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
        pid = spawn(fn -> load_workers_async(this, context, options) end)
        status = %{this.status| loading: :in_progress, state: :initialization}

        this = this
                |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], :loading)
                |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:directive)], :loading)

        this = %State{this| status: status, extended: Map.put(this.extended, :load_process, pid)}
        {:reply, {:ok, :loading}, this}
      else
        if Enum.member?(this.options.effective_options.features, :lazy_load) do
          Logger.info(fn -> {this.service.base().banner("Lazy Load Workers #{inspect this.environment_details}"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
          # nothing to do,
          this = this
                  |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], :online)
                  |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:directive)], :online)

          this = %State{this| status: %{this.status| loading: :complete, state: :ready}}
          {:reply, {:ok, :loaded}, this}
        else
          Logger.info(fn -> {this.service.base().banner("Load Workers"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
          :ok = load_workers_sync(this, context, options)
          this = this
                  |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], :online)
                  |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:directive)], :online)

          this = %State{this| status: %{this.status| loading: :complete, state: :ready}}
          {:reply, {:ok, :loaded}, this}
        end
      end
    end

    def load_complete(this, _source, _context) do
      status = %{this.status| loading: :complete, state: :ready}
      this = this
        |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], :online)
        |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:directive)], :online)

      this = %State{this| status: status, extended: Map.put(this.extended, :load_process, nil)}
      {:noreply, this}
    end

    #------------------------------------------------
    # load_workers_async
    #------------------------------------------------
    def load_workers_async(this, context, options) do
      Amnesia.Fragment.transaction do
        load_workers_async(this, this.service.worker_state_entity().worker_refs(this, context, options), context, options)
      end
    end
    def load_workers_async(this, nil, context, options), do: this.service.load_complete(this, {self(), node()}, context)
    def load_workers_async(this, sel, context, options) do
      values = Amnesia.Selection.values(sel)
      for value <- values do
        worker_add!(this, this.service.ref(value), context, options)
      end
      load_workers_async(this, Amnesia.Selection.next(sel), context, options)
    end

    #------------------------------------------------
    # load_workers_sync
    #------------------------------------------------
    def load_workers_sync(this, context, options) do
      Amnesia.Fragment.transaction do
        load_workers_sync(this, this.service.worker_state_entity().worker_refs(), context, options)
      end
    end
    def load_workers_sync(this, nil, _context, _options), do: :ok
    def load_workers_sync(this, sel, context, options) do
      values = Amnesia.Selection.values(sel)
      for value <- values do
        worker_add!(this, this.service.ref(value), context, options)
      end
      load_workers_sync(this, Amnesia.Selection.next(sel), context, options)
    end
end
