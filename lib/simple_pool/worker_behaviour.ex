defmodule Noizu.SimplePool.WorkerBehaviour do

  # Required Implementation
  @callback initial_state(any) :: Noizu.SimplePool.Worker.State.t
  @callback initialize(Noizu.SimplePool.Worker.State.t) :: Noizu.SimplePool.Worker.State.t
  @callback fetch(any, Noizu.SimplePool.Worker.State.t) :: {any, Noizu.SimplePool.Worker.State.t}
  @callback load(Noizu.SimplePool.Worker.State.t) :: {any, Noizu.SimplePool.Worker.State.t}

  # provided
  @callback start_link(any) :: any
  @callback init(any) :: any
  @callback handle_call(any, any, %Noizu.SimplePool.Worker.State{initialized: false}) :: any
  @callback handle_call({:fetch, any}, any, %Noizu.SimplePool.Worker.State{initialized: true}) :: any
  @callback handle_cast({:load}, any) :: any

  # @TODO handle_call callbacks

  @provided_methods [
      :start_link,
      :init,
      :terminate,
      :terminate_hook,
      :call_uninitialized,
      :call_fetch,
      :call_load,
      :migrate_init,
      :begin_migrate_hook,
      :handle_call_begin_migrate_worker
    ]

  defmacro __using__(options) do
    global_verbose = Dict.get(options, :verbose, false)
    module_verbose = Dict.get(options, :worker_verbose, false)
    only = Noizu.SimplePool.Behaviour.map_intersect(@provided_methods, Dict.get(options, :only, @provided_methods))
    override = Noizu.SimplePool.Behaviour.map_intersect(@provided_methods, Dict.get(options, :override, []))

    quote do
      import unquote(__MODULE__)
      require Logger
      @behaviour Noizu.SimplePool.WorkerBehaviour
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
      @server Module.concat([@base, "Server"])

      # @start_link
      if (unquote(only.start_link) && !unquote(override.start_link)) do
        def start_link(nmid) do
          if (unquote(global_verbose) || unquote(module_verbose)) do
            "************************************************\n" <>
            "* START_LINK #{__MODULE__} (#{inspect nmid})\n" <>
            "************************************************\n" |> Logger.info
          end
          GenServer.start_link(__MODULE__, nmid)
        end
      end # end start_link

      # @terminate
      if (unquote(only.terminate) && !unquote(override.terminate)) do
        def terminate(reason, state) do
          if (unquote(global_verbose) || unquote(module_verbose)) do
            "************************************************\n" <>
            "* TERMINATE #{__MODULE__} (#{inspect state.entity_ref })\n" <>
            "* Reason: #{inspect reason}" <>
            "************************************************\n" |> Logger.warn
          end
          @server.worker_lookup().dereg_worker!(@base, state.entity_ref)
          terminate_hook(reason, state)
        end
      end # end start_link

      # @terminate
      if (unquote(only.terminate_hook) && !unquote(override.terminate_hook)) do
        def terminate_hook(reason, state) do
          {:normal, state}
        end
      end # end start_link



      if (unquote(only.migrate_init) && !unquote(override.migrate_init)) do
        def migrate_init(initial_state) do
          initial_state
        end
      end

      if (unquote(only.begin_migrate_hook) && !unquote(override.begin_migrate_hook)) do
          def begin_migrate_hook(rnode, nmid, state)  do
            {:proceed, {rnode, state, {:migrate, nmid, state}}}
          end
      end

      if (unquote(only.handle_call_begin_migrate_worker) && !unquote(override.handle_call_begin_migrate_worker)) do
          def handle_call({:begin_migrate_worker, nmid, rnode}, _from, %Noizu.SimplePool.Worker.State{} = state) do
            if (rnode != node()) do
              if Node.ping(rnode) == :pong do
                case begin_migrate_hook(rnode, nmid, state) do
                  {:proceed, {forward_node, new_state, forward_identifier}} ->
                    response = @server.push_migrate(forward_identifier, forward_node)
                    {:stop,  {:shutdown,  {:process, :migrate}}, response, new_state}
                  {:proceed2, {forward_node, new_state, forward_identifier}} ->
                    response = @server.push_migrate(forward_identifier, forward_node)
                    {:reply, response, new_state}
                  {other, new_state} ->
                    {:reply, other, new_state}
                end
              else
                # TODO retry handling
                {:reply, {:error, {:remote_node, :unreachable}}, state}
              end
            else
              {:reply, {:ok, self()}, state}
            end
          end

          def handle_cast({:begin_migrate_worker, nmid, rnode}, %Noizu.SimplePool.Worker.State{} = state) do
            if (rnode != node()) do
              if Node.ping(rnode) == :pong do
                case begin_migrate_hook(rnode, nmid, state) do
                  {:proceed, {forward_node, new_state, forward_identifier}} ->
                    @server.push_migrate(forward_identifier, forward_node, :asynch)
                    {:stop, {:shutdown, {:process, :migrate}}, new_state}
                  {:proceed2, {forward_node, new_state, forward_identifier}} ->
                    @server.push_migrate(forward_identifier, forward_node, :asynch)
                    {:noreply, new_state}
                  {other, new_state} -> {:reply, other, new_state}
                end
              else
                # TODO retry handling
                {:noreply, state}
              end
            else
              {:noreply, state}
            end
          end # end def
      end # end if unquote

      # @init
      if (unquote(only.init) && !unquote(override.init)) do
        def init({:migrate, nmid, %Noizu.SimplePool.Worker.State{} = initial_state}) do
          if (unquote(global_verbose) || unquote(module_verbose)) do
            "************************************************\n" <>
            "* MIGRATE #{__MODULE__} (#{inspect nmid })\n" <>
            "************************************************\n" |> Logger.info
          end
          @server.worker_lookup().reg_worker!(@base, nmid, self())
          {:ok, migrate_init(initial_state)}
        end

        def init(nmid) do
          if (unquote(global_verbose) || unquote(module_verbose)) do
            "************************************************\n" <>
            "* INIT #{__MODULE__} (#{inspect nmid })\n" <>
            "************************************************\n" |> Logger.info
          end
          @server.worker_lookup().reg_worker!(@base, nmid, self())
          {:ok, initial_state(nmid)}
        end
      end # end init

        #=========================================================================
        #=========================================================================
        # Handlers
        #=========================================================================
        #=========================================================================
      # @call_uninitialized
      if (unquote(only.call_uninitialized) && !unquote(override.call_uninitialized)) do
        def handle_call(any_call, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          state = initialize(state)
          if state.initialized do
            handle_call(any_call, from, state)
          else
            {:reply, :initilization_failed, state}
          end
        end

        def handle_cast(any_call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          state = initialize(state)
          if state.initialized do
            handle_cast(any_call, state)
          else
            {:noreply, state}
          end
        end

      end # end call_uninitialized

      # @call_fetch
      if (unquote(only.call_fetch) && !unquote(override.call_fetch)) do
        def handle_call({:fetch, details}, _from, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
          {response, state} = fetch(details, state)
          {:reply, response, state}
        end
      end # end call_fetch

      # @call_load
      if (unquote(only.call_load) && !unquote(override.call_load)) do
        def handle_cast({:load}, state) do
          {_status_and_details, state} = load(state)
          {:noreply, state}
        end
      end # end call_load

      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
    end # end quote
  end # end __before_compile__

end
