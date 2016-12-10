defmodule Noizu.SimplePool.WorkerBehaviour do

  @callback initial_state(any) :: Noizu.SimplePool.Worker.State.t
  @callback initialize(Noizu.SimplePool.Worker.State.t) :: Noizu.SimplePool.Worker.State.t
  @callback fetch(any, Noizu.SimplePool.Worker.State.t) :: {any, Noizu.SimplePool.Worker.State.t}
  @callback load(Noizu.SimplePool.Worker.State.t) :: {any, Noizu.SimplePool.Worker.State.t}

  defmacro __using__(options) do
    global_verbose = Dict.get(options, :verbose, false)
    module_verbose = Dict.get(options, :worker_verbose, false)

    quote do
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.WorkerBehaviour

      def start_link(nmid) do
        if (unquote(global_verbose) || unquote(module_verbose)) do
          "************************************************\n" <>
          "* START_LINK #{__MODULE__} (#{inspect nmid})\n" <>
          "************************************************\n" |> IO.puts()
        end
        GenServer.start_link(__MODULE__, nmid)
      end

      def init(nmid) do
        if (unquote(global_verbose) || unquote(module_verbose)) do
          "************************************************\n" <>
          "* INIT #{__MODULE__} (#{inspect nmid })\n" <>
          "************************************************\n" |> IO.puts()
        end
        {:ok, initial_state(nmid)}
      end

      #=========================================================================
      #=========================================================================
      # Handlers
      #=========================================================================
      #=========================================================================
      def handle_call({:fetch, details}, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
        state = initialize(state)
        if state.initialized do
          handle_call({:fetch, details}, from, state)
        else
          {:reply, :initilization_failed, state}
        end
      end

      def handle_call({:fetch, details}, _from, %{initialized: true} = state) do
        {response, state} = fetch(details, state)
        {:reply, response, state}
      end

      def handle_cast({:load}, state) do
        {_status_and_details, state} = load(state)
        {:noreply, state}
      end

      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
    end # end quote
  end # end __before_compile__

end
