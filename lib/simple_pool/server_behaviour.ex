defmodule Noizu.SimplePool.ServerBehaviour do

  # Must be implemented
  @callback lazy_load(Noizu.SimplePool.Server.State.t) :: {any, Noizu.SimplePool.Server.State.t}

  # Provided
  @callback load() :: any

  @callback status() :: any

  @callback generate(:nmid) :: any

  @callback add!(any) :: any
  @callback add!(any, :asynch) :: any

  @callback remove!(any) :: any
  @callback remove!(any, :asynch) :: any
  @callback remove(any, :worker, any) :: any

  @callback fetch!(any, any)  :: any
  @callback fetch!(any, any, :asynch, any) :: any

  @callback pid_or_spawn(any) :: {:ok, any} | {:error, any}

  @callback start_link(any, any) :: any
  @callback init(any) :: any
  @callback terminate(any, any, any) :: any
  @callback alive?(any, :worker) :: any
  @callback add(any, :worker, any) :: any
  @callback start(any, :worker, any) :: any
  @callback start(any, any, :worker, any) :: any
  @callback worker_pid!(any) :: any

  @callback handle_call({:load_complete, {any, any}}, any, Noizu.SimplePool.Server.State.t) :: any
  @callback handle_call({:status}, any, Noizu.SimplePool.Server.State.t) :: any
  @callback handle_call({:generate, :nmid}, any, Noizu.SimplePool.Server.State.t) :: any
  @callback handle_call({:add_worker, any}, any, Noizu.SimplePool.Server.State.t) :: any
  @callback handle_call({:remove_worker, any}, any, Noizu.SimplePool.Server.State.t) :: any
  @callback handle_call({:fetch, any, any}, any, Noizu.SimplePool.Server.State.t) :: any
  @callback handle_cast({:load}, Noizu.SimplePool.Server.State.t) :: any

  @provided_methods [
    :start_link,
    :init,
    :terminate,
    :load,
    :status,
    :generate,
    :add!,
    :remove!,
    :fetch!,
    :pid_or_spawn!,
    :alive?,
    :add,
    :start,
    :remove,
    :worker_pid!,
    :call_load_complete,
    :call_status,
    :call_generate,
    :call_add_worker,
    :call_remove_worker,
    :call_fetch,
    :cast_load
  ]

  defmacro __using__(options) do
    global_verbose = Dict.get(options, :verbose, false)
    module_verbose = Dict.get(options, :server_verbose, false)
    only = Noizu.SimplePool.Behaviour.map_intersect(@provided_methods, Dict.get(options, :only, @provided_methods))
    override = Noizu.SimplePool.Behaviour.map_intersect(@provided_methods, Dict.get(options, :override, []))
    asynch_load = Dict.get(options, :asynch_load, false)

    quote do
      import unquote(__MODULE__)
      require Amnesia
      require Amnesia.Fragment

      @behaviour Noizu.SimplePool.ServerBehaviour
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
      @worker_supervisor Module.concat([@base, "WorkerSupervisor"])
      #=========================================================================
      #=========================================================================
      # Genserver Lifecycle
      #=========================================================================
      #=========================================================================

    # @start_link
    if (unquote(only.start_link) && !unquote(override.start_link)) do
      def start_link(sup, nmid_generator) do
        if (unquote(global_verbose) || unquote(module_verbose)) do
          "************************************************\n" <>
          "* START_LINK #{__MODULE__} (#{inspect {sup, nmid_generator}})\n" <>
          "************************************************\n" |> IO.puts()
        end
        GenServer.start_link(__MODULE__, {sup, nmid_generator}, name: __MODULE__)
      end
    end # end start_link

    # @init
    if (unquote(only.init) && !unquote(override.init)) do
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
    end # end init

    # @terminate
    if (unquote(only.terminate) && !unquote(override.terminate)) do
      def terminate(reason, request, state) do
        :ok
      end
    end # end terminate


      #=========================================================================
      #=========================================================================
      #  Common Convienence Methods
      #=========================================================================
      #=========================================================================

      # @load
      if (unquote(only.load) && !unquote(override.load)) do
        @doc """
          Load pool from datastore.
        """
        def load() do
          GenServer.call(__MODULE__, {:load})
        end
      end # end load

      # @status
      if (unquote(only.status) && !unquote(override.status)) do

        @doc """
          Retrieve pool status
        """
        def status() do
          GenServer.call(__MODULE__, {:status})
        end
      end # end status

      # @generate
      if (unquote(only.generate) && !unquote(override.generate)) do

        @doc """
          Generate unique nmid value.
        """
        def generate(:nmid) do
          # Assuming uncapped sequence, and no more than 99 nodes and 999 processes per node
          GenServer.call(__MODULE__, {:generate, :nmid})
        end
      end # end generate

      # @add!
      if (unquote(only.add!) && !unquote(override.add!)) do

        @doc """
          Add worker pool keyed by nmid. Worker must know how to load itself, and provide a load method.
        """
        def add!(nmid) do
          GenServer.call(__MODULE__, {:add_worker, nmid})
        end
      end # end add!

      # @remove!
      if (unquote(only.remove!) && !unquote(override.remove!)) do

        @doc """
          Remove worker process.
        """
        def remove!(nmid) do
          GenServer.call(__MODULE__, {:remove_worker, nmid})
        end
      end # end remove!

      # @fetch!
      if (unquote(only.fetch!) && !unquote(override.fetch!)) do

        @doc """
          Fetch information about worker. Exact information is class dependent.
        """
        def fetch!(nmid, details \\ :default) do
          case pid_or_spawn!(nmid) do
            {:ok, pid} -> GenServer.call(pid, {:fetch, details})
            _ -> :not_found
          end
        end
      end # end fetch!

      # @pid_or_spawn!
      if (unquote(only.pid_or_spawn!) && !unquote(override.pid_or_spawn!)) do

        @doc """
          return cached pid for process or spawn if dead and return newly created pid.
        """
        def pid_or_spawn!(nmid) do
          case alive?(nmid, :worker) do
            {false, :nil} -> add!(nmid)
            {true, pid} -> {:ok, pid}
          end
        end
      end # end pid_or_spawn!

      # @remove!
      if (unquote(only.remove!) && !unquote(override.remove!)) do

        @doc """
          Remove worker Asynch
        """
        def remove!(nmid, :asynch) do
          GenServer.cast(__MODULE__, {:remove_worker, nmid})
        end
      end # end remove!

      # @add!
      if (unquote(only.add!) && !unquote(override.add!)) do

        @doc """
          Add worker process Asynch
        """
        def add!(nmid, :asynch) do
          GenServer.cast(__MODULE__, {:add_worker, nmid})
        end
      end # end add!

      # @fetch!
      if (unquote(only.fetch!) && !unquote(override.fetch!)) do

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
      end # end fetch!

      # @alive?
      if (unquote(only.alive?) && !unquote(override.alive?)) do

        #-----------------------------------------------------------------------------
        # alive/2
        #-----------------------------------------------------------------------------
        def alive?(:nil, :worker) do
          {false, :nil}
        end

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

        def alive?(nmid, :worker) when is_bitstring(nmid) do
          alive?(nmid |> Integer.parse() |> elem(0), :worker)
        end
      end # end alive?


        #-----------------------------------------------------------------------------
        # add/3
        #-----------------------------------------------------------------------------
      # @add
      if (unquote(only.add) && !unquote(override.add)) do
        defp add(nmid, :worker, sup) do
          case alive?(nmid, :worker) do
              {:false, :nil} -> start(nmid, :worker, sup)
              {:true, pid} -> {:ok, pid}
          end
        end
      end # end add


        #-----------------------------------------------------------------------------
        # start/3
        #-----------------------------------------------------------------------------
      # @start
      if (unquote(only.start) && !unquote(override.start)) do
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
              Logger.error("#{__MODULE__} unable to start #{inspect nmid}")
              error
          end
        end

        defp start(nmid, :worker, sup) when is_bitstring(nmid) do
          start(nmid |> Integer.parse() |> elem(0), :worker, sup)
        end

      end # end start

        #-----------------------------------------------------------------------------
        # start/4
        #-----------------------------------------------------------------------------
        # @start
        if (unquote(only.start) && !unquote(override.start)) do
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
              Logger.error("#{__MODULE__} unable to start #{inspect nmid}")
              error
          end
        end

        defp start(nmid, arguments, :worker, sup) when is_bitstring(nmid) do
          start(nmid |> Integer.parse() |> elem(0), arguments, :worker, sup)
        end
      end # end start

        #-----------------------------------------------------------------------------
        # remove/3
        #-----------------------------------------------------------------------------

        # @remove
        if (unquote(only.remove) && !unquote(override.remove)) do
        defp remove(nmid, :worker, sup) when is_number(nmid) or is_tuple(nmid) do
          Supervisor.terminate_child(sup, nmid)
          Supervisor.delete_child(sup, nmid)
          :ets.delete(@base.lookup_table(), nmid)
        end
        defp remove(nmid, :worker, sup) when is_bitstring(nmid) do
          remove(nmid |> Integer.parse() |> elem(0), :worker, sup)
        end

      end # end remove

      # @worker_pid!
      if (unquote(only.worker_pid!) && !unquote(override.worker_pid!)) do


        @doc """
          Add worker pool keyed by nmid. Worker must know how to load itself, and provide a load method.
        """
        def worker_pid!(nmid) when is_bitstring(nmid) do
          String.to_integer(nmid)
            |> worker_pid!()
        end

        def worker_pid!(nmid) when is_integer(nmid) or is_tuple(nmid) do
          case alive?(nmid, :worker) do
            {false, :nil} ->
              # Call Server to spawn worker and then fetch results.
              add!(nmid)
            {true, pid} ->
              # Call worker directly
              {:ok, pid}
          end
        end
      end # end worker_pid!



        #=========================================================================
        #=========================================================================
        # Common Call Handlers for SimpleServer
        #=========================================================================
        #=========================================================================
      # @call_load_complete
      if (unquote(only.call_load_complete) && !unquote(override.call_load_complete)) do
        def handle_call({:load_complete, {outcome, details}}, _from, state) do
            state = if outcome == :ok do
              %Noizu.SimplePool.Server.State{state| status: :online, status_details: details}
            else
              %Noizu.SimplePool.Server.State{state| status: :degrade, status_details: details}
            end
            {:reply, :ok, state}
        end
      end # end call_load_complete

      # @call_status
      if (unquote(only.call_status) && !unquote(override.call_status)) do
        def handle_call({:status}, _from, %Noizu.SimplePool.Server.State{status: status} = state) do
          {:reply, status, state}
        end
      end # end call_status

      # @call_generte
      if (unquote(only.call_generate) && !unquote(override.call_generate)) do
        def handle_call({:generate, :nmid}, _from, %Noizu.SimplePool.Server.State{nmid_generator: {{node, process}, sequence}} = state) do
          {nmid, state} = @base.generate_nmid(state)
          {:reply, nmid, state}
        end
      end # end call_generate

      # @call_add_worker
      if (unquote(only.call_add_worker) && !unquote(override.call_add_worker)) do
        def handle_call({:add_worker, nmid}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
          # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
          response = add(nmid, :worker, sup)
          {:reply, response, state}
        end
      end # end call_add_worker

      # @call_remove_worker
      if (unquote(only.call_remove_worker) && !unquote(override.call_remove_worker)) do
        def handle_call({:remove_worker, nmid}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
          # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
          response = remove(nmid, :worker, sup)
          {:reply, response, state}
        end
      end # end call_remove_worker

      # @call_fetch
      if (unquote(only.call_fetch) && !unquote(override.call_fetch)) do
        def handle_call({:fetch, nmid, details}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
              {:ok, pid} = add(nmid, :worker, sup)
              response = GenServer.call(pid, {:fetch, details})
              {:reply, response, state}
        end
      end # end call_fetch

        #=========================================================================
        #=========================================================================
        # Common Cast Handlers for SimpleServer
        #=========================================================================
        #=========================================================================

      # @call_load
      if (unquote(only.call_load) && !unquote(override.call_load)) do

        if (!unquote(asynch_load)) do
          def handle_cast({:load}, state) do
            IO.puts "INITIAL LOAD: #{inspect state}"
            {:noreply, state}
          end
        end

        if (unquote(asynch_load)) do
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
