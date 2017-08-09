defmodule Noizu.SimplePool.Server.ProviderBehaviour.Default do
    alias Noizu.SimplePool.Server.State
    require Logger
    use Amnesia
    #---------------------------------------------------------------------------
    # GenServer Lifecycle
    #---------------------------------------------------------------------------
    def init(server, sup, options \\ nil) do
      server.enable_server!(node())
      state = %State{
          pool: sup,
          server: server,
          status_details: :pending,
          extended: %{},
          options: options
        }
      {:ok, state}
    end

    def terminate(_reason, %State{} = state) do
      state.server.base().banner("Terminate #{inspect state, pretty: true}")
      state.server.disable_server!(node())
      :ok
    end

    #---------------------------------------------------------------------------
    # Startup: Lazy Loading/Asynch Load/Immediate Load strategies.
    # Blocking/Lazy Initialization, Loading Strategy.
    #---------------------------------------------------------------------------
    def status(server, context), do: server.internal_call(:status, context)
    def load(server, settings, context), do: server.internal_call({:load, settings}, context)

    #---------------------------------------------------------------------------
    # Internal Routing
    #---------------------------------------------------------------------------
    # Final steps: @TODO support for load, status, add_worker!, remove_worker!

    #---------------------------------------------------------------------------
    # Internal Routing - internal_call_handler
    #---------------------------------------------------------------------------
    def internal_call_handler({:load, options}, context, _from, %State{} = state), do: load_workers(options, context, state)
    def internal_call_handler({:worker_add!, ref, options}, context, _from, %State{} = state), do: worker_add!(ref, options, context, state)
    def internal_call_handler(call, context, _from, %State{} = state) do
      if context do
        Logger.error("#{Map.get(context, :token, :token_not_found)}: #{state.server} unsupported call(#{inspect call})")
      else
        Logger.error(" #{state.server} unsupported call(#{inspect call})")
      end
      {:reply, {:error, {:unsupported, call}}, state}
    end
    #---------------------------------------------------------------------------
    # Internal Routing - internal_cast_handler
    #---------------------------------------------------------------------------
    def internal_cast_handler({:worker_remove!, ref, options}, context, %State{} = state), do: worker_remove!(ref, options, context, state)
    def internal_cast_handler(call, context, %State{} = state) do
      if context do
        Logger.error("#{Map.get(context, :token, :token_not_found)}: #{state.server} unsupported cast(#{inspect call})")
      else
        Logger.error(" #{state.server} unsupported cast(#{inspect call})")
      end
      {:reply, {:error, {:unsupported, call}}, state}
    end

    #---------------------------------------------------------------------------
    # Internal Routing - internal_info_handler
    #---------------------------------------------------------------------------
    def internal_info_handler(call, context, %State{} = state) do
      if context do
        Logger.error("#{Map.get(context, :token, :token_not_found)}: #{state.server} unsupported nfo(#{inspect call})")
      else
        Logger.error(" #{state.server} unsupported info(#{inspect call})")
      end
      {:reply, {:error, {:unsupported, call}}, state}
    end

    #---------------------------------------------------------------------------
    # Internal Implementations
    #---------------------------------------------------------------------------

    #------------------------------------------------
    # worker_add!()
    #------------------------------------------------
    def worker_add!(ref, options, context, state) do
      if Enum.member?(state.options.effective_options.features, :asynch_load) do
        state.server.worker_sup_start(ref, state.pool, context)
      else
        case state.server.worker_sup_start(ref, state.pool, context) do
          {:ok, pid} -> GenServer.cast(pid, {:s, {:load, options}, context})
            {:reply, {:ok, pid}, state}
          error -> {:reply, error, state}
        end
      end
    end

    #------------------------------------------------
    # worker_remove!
    #------------------------------------------------
    def worker_remove!(ref, _options, context, state) do
      state.server.worker_sup_remove(ref, state.pool, context)
    end

    #------------------------------------------------
    # load_workers
    #------------------------------------------------
    def load_workers(options, context, state) do
      if Enum.member?(state.options.effective_options.features, :asynch_load) do
        pid = spawn(fn -> load_workers_asynch(options, context, state) end)
        status = %{state.status| loading: :in_progress, state: :initialization}
        state = %State{state| status: status, extended: Map.put(state.extended, :load_process, pid)}
        {:reply, {:ok, :loading}, state}
      else
        if Enum.member?(state.options.effective_options.features, :lazy_load) do
          # nothing to do,
          state = %State{state| status: %{state.status| loading: :complete, state: :ready}}
          {:reply, {:ok, :loaded}, state}
        else
          :ok = load_workers_synch(options, context, state)
          state = %State{state| status: %{state.status| loading: :complete, state: :ready}}
          {:reply, {:ok, :loaded}, state}
        end
      end
    end

    def load_complete(_context, state) do
      status = %{state.status| loading: :complete, state: :ready}
      state = %State{state| status: status, extended: Map.put(state.extended, :load_process, nil)}
      {:noreply, state}
    end

    #------------------------------------------------
    # load_workers_asynch
    #------------------------------------------------
    def load_workers_asynch(options, context, state) do
      Amnesia.Fragment.transaction do
        load_workers_asynch(state.server.worker_state_entity().worker_refs(), options, context, state)
      end
    end
    def load_workers_asynch(nil, _options, context, state), do: state.server.load_complete({self(), node()}, context)
    def load_workers_asynch(sel, options, context, state) do
      values = Amnesia.Selection.values(sel)
      for value <- values do
        ref = state.server.ref(value)
        worker_add!(ref, options, context, state)
      end
      load_workers_asynch(Amnesia.Selection.next(sel), options, context, state)
    end

    #------------------------------------------------
    # load_workers_synch
    #------------------------------------------------
    def load_workers_synch(options, context, state) do
      Amnesia.Fragment.transaction do
        load_workers_synch(state.server.worker_state_entity().worker_refs(), options, context, state)
      end
    end
    def load_workers_synch(nil, _options, _context, _state), do: :ok
    def load_workers_synch(sel, options, context, state) do
      values = Amnesia.Selection.values(sel)
      for value <- values do
        ref = state.server.ref(value)
        worker_add!(ref, options, context, state)
      end
      load_workers_synch(Amnesia.Selection.next(sel), options, context, state)
    end
end
