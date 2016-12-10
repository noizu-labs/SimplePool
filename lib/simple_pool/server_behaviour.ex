defmodule Noizu.SimplePool.ServerBehaviour do
  @callback lazy_load(Noizu.SimplePool.Server.State.t) :: Noizu.SimplePool.Server.State.t

  @callback load() :: any
  @callback lazy_load(Noizu.SimplePool.Server.State.t) :: {any, Noizu.SimplePool.Server.State.t}

  @callback status() :: any

  @callback generate(:nmid) :: any

  @callback add!(any) :: any
  @callback add!(any, :asynch) :: any

  @callback remove!(any) :: any
  @callback remove!(any, :asynch) :: any

  @callback fetch!(any, any)  :: any
  @callback fetch!(any, any, :asynch, any) :: any

  @callback alive?(integer, atom) :: any

  defmacro __using__(options) do
    global_verbose = Dict.get(options, :verbose, false)
    module_verbose = Dict.get(options, :server_verbose, false)

    quote do
      import unquote(__MODULE__)
      require Amnesia
      require Amnesia.Fragment

      @behaviour Noizu.SimplePool.ServerBehaviour
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat

      #=========================================================================
      #=========================================================================
      # Genserver Lifecycle
      #=========================================================================
      #=========================================================================

      def start_link(sup, nmid_generator) do
        if (unquote(global_verbose) || unquote(module_verbose)) do
          "************************************************\n" <>
          "* START_LINK #{__MODULE__} (#{inspect {sup, nmid_generator}})\n" <>
          "************************************************\n" |> IO.puts()
        end
        GenServer.start_link(__MODULE__, {sup, nmid_generator}, name: __MODULE__)
      end

      def init({sup, {node, process}} = p) do
        if (unquote(global_verbose) || unquote(module_verbose)) do
          "************************************************\n" <>
          "* INIT #{__MODULE__} (#{inspect {sup, {node, process}}})\n" <>
          "************************************************\n" |> IO.puts()
        end
        {{node, process}, sequence} = @base.book_keeping_init()

        state = %Noizu.SimplePool.Server.State{
          pool: sup,
          nmid_generator: {{node, process}, sequence},
          status_details: nil,
          status: :uninitialized
        }

        {:ok, state}
      end

      def terminate(reason, request, state) do
        :ok
      end

      #=========================================================================
      #=========================================================================
      #  Common Convienence Methods
      #=========================================================================
      #=========================================================================

        @doc """
          Load pool from datastore.
        """
        def load() do
          GenServer.call(__MODULE__, {:load})
        end

        @doc """
          Retrieve pool status
        """
        def status() do
          GenServer.call(__MODULE__, {:status})
        end

        @doc """
          Generate unique nmid value.
        """
        def generate(:nmid) do
          # Assuming uncapped sequence, and no more than 99 nodes and 999 processes per node
          GenServer.call(__MODULE__, {:generate, :nmid})
        end

        @doc """
          Add worker pool keyed by nmid. Worker must know how to load itself, and provide a load method.
        """
        def add!(nmid) do
          GenServer.call(__MODULE__, {:add_worker, nmid})
        end

        @doc """
          Remove worker process.
        """
        def remove!(nmid) do
          GenServer.call(__MODULE__, {:remove_worker, nmid})
        end

        @doc """
          Fetch information about worker. Exact information is class dependent.
        """
        def fetch!(nmid, details \\ :default) do
          # If worker already exists and is alive can call directly with out
          # needing to hit the running server process. (TODO make alive? a macro)
          case alive?(nmid, :worker) do
            {false, :nil} ->
              # Call Server to spawn worker and then fetch results.
              GenServer.call(__MODULE__, {:fetch, nmid, details})
            {true, pid} ->
              # Call worker directly
              GenServer.call(pid, {:fetch, details})
          end
        end

        @doc """
          Remove worker Asynch
        """
        def remove!(nmid, :asynch) do
          GenServer.cast(__MODULE__, {:remove_worker, nmid})
        end

        @doc """
          Add worker process Asynch
        """
        def add!(nmid, :asynch) do
          GenServer.cast(__MODULE__, {:add_worker, nmid})
        end

        @doc """
          Fetch worker process Asynch. (Once worker ahs prepared requested data it performs a callback)
        """
        def fetch!(nmid, details, :asynch, caller \\ :current) do
          caller = if caller == :current do
            self()
          else
            caller
          end

          # Todo - Implement as macro
          case alive?(nmid, :worker) do
            {false, :nil} ->
              # Call Server to spawn worker and then fetch results.
              GenServer.cast(__MODULE__, {:fetch, nmid, details, caller})
            {true, pid} ->
              # Call worker directly
              GenServer.cast(pid, {:fetch, nmid, details, caller})
          end
        end

        #-----------------------------------------------------------------------------
        # alive/2
        #-----------------------------------------------------------------------------
        def alive?(nmid, :worker) when is_number(nmid) or is_tuple(nmid) do
          case :ets.info(@base.lookup_table()) do
            :undefined -> {false, :nil}
            _ ->
              case :ets.lookup(@base.lookup_table(), nmid) do
                 [{_key, pid}] ->
                    if Process.alive?(pid) do
                      {true, pid}
                    else
                      {false, :nil}
                    end
                  [] -> {false, :nil}
              end
          end
        end

        def alive?(:nil, :worker) do
          {false, :nil}
        end

        def alive?(nmid, :worker) when is_bitstring(nmid) do
          alive?(nmid |> Integer.parse() |> elem(0), :worker)
        end

        #-----------------------------------------------------------------------------
        # add/3
        #-----------------------------------------------------------------------------
        defp add(nmid, :worker, sup) do
          case alive?(nmid, :worker) do
              {:false, :nil} -> start(nmid, :worker, sup)
              {:true, pid} -> {:ok, pid}
          end
        end

        #-----------------------------------------------------------------------------
        # start/3
        #-----------------------------------------------------------------------------
        defp start(nmid, :worker, sup) when is_number(nmid) or is_tuple(nmid) do
          childSpec = @worker_supervisor.child(nmid)
          case Supervisor.start_child(sup, childSpec) do
            {:ok, pid} ->
              :ets.insert(@base.lookup_table(), {nmid, pid})
              {:ok, pid}
            {:error, {:already_started, pid}} ->
              :ets.insert(@base.lookup_table(), {nmid, pid})
              {:ok, pid}
            error ->
              error
          end
        end

        defp start(nmid, :worker, sup) when is_bitstring(nmid) do
          start(nmid |> Integer.parse() |> elem(0), :worker, sup)
        end

        #-----------------------------------------------------------------------------
        # start/4
        #-----------------------------------------------------------------------------
        defp start(nmid, arguments, :worker, sup) when is_number(nmid) or is_tuple(nmid) do
          childSpec = @worker_supervisor.child(nmid, arguments)
          case Supervisor.start_child(sup, childSpec) do
            {:ok, pid} ->
              :ets.insert(@base.lookup_table(), {nmid, pid})
              {:ok, pid}
            {:error, {:already_started, pid}} ->
              :ets.insert(@base.lookup_table(), {nmid, pid})
              {:ok, pid}
            error ->
              error
          end
        end

        defp start(nmid, arguments, :worker, sup) when is_bitstring(nmid) do
          start(nmid |> Integer.parse() |> elem(0), arguments, :worker, sup)
        end

        #-----------------------------------------------------------------------------
        # remove/3
        #-----------------------------------------------------------------------------
        defp remove(nmid, :worker, sup) when is_number(nmid) or is_tuple(nmid) do
          Supervisor.terminate_child(sup, nmid)
          Supervisor.delete_child(sup, nmid)
          :ets.delete(@base.lookup_table(), nmid)
        end
        defp remove(nmid, :worker, sup) when is_bitstring(nmid) do
          remove(nmid |> Integer.parse() |> elem(0), :worker, sup)
        end

        #=========================================================================
        #=========================================================================
        # Common Call Handlers for SimpleServer
        #=========================================================================
        #=========================================================================
        def handle_call({:load_complete, {outcome, details}}, _from, state) do
            state = if outcome == :ok do
              %Noizu.SimplePool.Server.State{state| status: :online, status_details: details}
            else
              %Noizu.SimplePool.Server.State{state| status: :degrade, status_details: details}
            end
            {:reply, :ok, state}
        end

        def handle_call({:status}, _from, %Noizu.SimplePool.Server.State{status: status} = state) do
          {:reply, status, state}
        end

        def handle_call({:generate, :nmid}, _from, %Noizu.SimplePool.Server.State{nmid_generator: {{node, process}, sequence}} = state) do
          {nmid, state} = @base.generate_nmid(state)
          {:reply, nmid, state}
        end

        def handle_call({:add_worker, nmid}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
          # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
          response = add(nmid, :worker, sup)
          {:reply, response, state}
        end

        def handle_call({:remove_worker, nmid}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
          # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
          response = remove(nmid, :worker, sup)
          {:reply, response, state}
        end

        def handle_call({:fetch, nmid, details}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
              {:ok, pid} = add(nmid, :worker, sup)
              response = GenServer.call(pid, {:fetch, details})
              {:reply, response, state}
        end

        #=========================================================================
        #=========================================================================
        # Common Cast Handlers for SimpleServer
        #=========================================================================
        #=========================================================================
        def handle_cast({:load}, state) do
          IO.puts "INITIAL LOAD: #{inspect state}"
          {:noreply, state}
        end

        def handle_cast({:load}, %Noizu.SimplePool.Server.State{status: status} = state) do
          if status == :uninitialized do
            state = %Noizu.SimplePool.Server.State{state| status: :initializing}

            spawn fn ->
              {status, details} = lazy_load(state)
              GenServer.call(__MODULE__, {:load_complete, {status, details}})
            end

            {:noreply, state}
          else
            {:noreply, state}
          end
        end

      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
    end # end quote
  end # end __before_compile__


end
