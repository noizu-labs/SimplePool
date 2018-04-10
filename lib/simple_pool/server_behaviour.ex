defmodule Noizu.SimplePool.ServerBehaviour do
  # Must be implemented
  @callback lazy_load(Noizu.SimplePool.Server.State.t) :: {any, Noizu.SimplePool.Server.State.t}

  @callback init_hook(any) :: {:ok, any} | {:error, any}

  # Provided
  @callback load() :: any

  @callback lookup_identifier(any) :: {:ok, any} | {:error, any}

  @callback status() :: any

  @callback generate(:nmid) :: any

  @callback normid(any) :: any

  @callback add!(any) :: any
  @callback add!(any, :asynch) :: any

  @callback remove!(any) :: any
  @callback remove!(any, :asynch) :: any
  @callback remove(any, :worker, any) :: any

  @callback fetch!(any, any)  :: any
  @callback fetch!(any, any, :asynch, any) :: any

  @callback get_pid(any) :: {:ok, any} | {:error, any}
  @callback pid_or_spawn!(any) :: {:ok, any} | {:error, any}

  @callback start_link(any, any) :: any
  @callback init(any) :: any
  @callback terminate(any, any) :: any
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
    :init_hook,
    :terminate,
    :load,
    :status,
    :generate,
    :lookup_identifier,
    :normid,
    :add!,
    :remove!,
    :fetch!,
    :get_pid,
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
    :cast_load,
    :migrate!,
    :add_distributed!,
    :call_add_worker_distributed,
    :add_distributed,
    :start_distributed,
    :handle_call_start,
    :handle_call_begin_migrate_worker,
    :push_migrate
  ]

  defmacro __using__(options) do
    global_verbose = Dict.get(options, :verbose, false)
    module_verbose = Dict.get(options, :server_verbose, false)
    only = Noizu.SimplePool.Behaviour.map_intersect(@provided_methods, Dict.get(options, :only, @provided_methods))
    override = Noizu.SimplePool.Behaviour.map_intersect(@provided_methods, Dict.get(options, :override, []))
    asynch_load = Dict.get(options, :asynch_load, false)
    distributed? = Dict.get(options, :user_distributed_calls, false)
    worker_lookup_handler = Dict.get(options, :worker_lookup_handler, Noizu.SimplePool.WorkerLookupBehaviour.DefaultImplementation)

    quote do
      import unquote(__MODULE__)
      require Amnesia
      require Amnesia.Fragment
      require Amnesia.Helper
      require Logger

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
          "* START_LINK #{__MODULE__} (#{inspect {@worker_supervisor, nmid_generator}})\n" <>
          "************************************************\n" |> Logger.info
        end
        GenServer.start_link(__MODULE__, {@worker_supervisor, nmid_generator}, name: __MODULE__, restart: :permanent)
      end
    end # end start_link

    # @init_hook
    #@TODO push some of this out to a Behaviour Provider
    if (unquote(only.init_hook) && !unquote(override.init_hook)) do
      def init_hook(state) do
        {:ok, state}
      end
    end # end init_hook

    # @init
    if (unquote(only.init) && !unquote(override.init)) do
      def init({sup, {node, process}} = p) do
        if (unquote(global_verbose) || unquote(module_verbose)) do
          "************************************************\n" <>
          "* INIT #{__MODULE__} (#{inspect {@worker_supervisor, {node, process}}})\n" <>
          "************************************************\n" |> Logger.info
        end
        {{node, process}, sequence} = @base.book_keeping_init()
        unquote(worker_lookup_handler).update_endpoint!(@base)
        init_hook(%Noizu.SimplePool.Server.State{
          pool: @worker_supervisor,
          nmid_generator: {{node, process}, sequence},
          status_details: nil,
          status: :uninitialized
        })
      end
    end # end init

    # @terminate
    if (unquote(only.terminate) && !unquote(override.terminate)) do
      def terminate(reason, state) do
        reason
      end
    end # end terminate

      def s_call!(worker, call, timeout \\ 30_000) do
        worker = normid(worker)
        try do
          case pid_or_spawn!(worker) do
            {:ok, pid} -> GenServer.call(pid, call, timeout)
            _ -> :error
          end # end case
        catch
          :exit, e ->
            case e do
              {:timeout, c} ->
                Logger.info "#{@base} - unresponsive worker (#{inspect worker}) #{inspect e}"
                :error
                _ ->
                  Logger.error "#{@base} - dead worker: caught (#{inspect e})"
                  unquote(worker_lookup_handler).dereg_worker!(@base, worker)
                  #case pid_or_spawn!(worker) do
                  #  {:ok, pid} -> GenServer.call(pid, call, timeout)
                  #  _ -> :error
                  #end  # end case
                  :error
            end
        end # end try
      end # end s_call!

      def s_cast!(worker, call) do
        worker = normid(worker)
        try do
          case pid_or_spawn!(worker) do
            {:ok, pid} -> GenServer.cast(pid, call)
            _ -> :error
          end
        catch
          :exit, e ->

            case e do
              {:timeout, c} ->
                Logger.info "#{@base} - unresponsive worker (#{inspect worker}) #{inspect e}"
                :error
                _ ->
                  Logger.warn "#{@base} - dead worker (#{inspect worker})"
                  unquote(worker_lookup_handler).dereg_worker!(@base, worker)
                  #case pid_or_spawn!(worker) do
                  #  {:ok, pid} -> GenServer.cast(pid, call)
                  #  _ -> :error
                  #end # end case
                  :error
            end


        end # end try
      end # end s_cast!

      def s_call(worker, call, timeout \\ 30_000) do
        worker = normid(worker)
        try do
          case get_pid(worker) do
            {:ok, pid} -> GenServer.call(pid, call, timeout)
            _ -> :error
          end
        catch
          :exit, e ->

            case e do
              {:timeout, c} ->
                Logger.info "#{@base} - unresponsive worker (#{inspect worker}) #{inspect e}"
                :error
                _ ->
                  Logger.warn "#{@base} - dead worker (#{inspect worker})"
                  unquote(worker_lookup_handler).dereg_worker!(@base, worker)
                  #case pid_or_spawn!(worker) do
                  #  {:ok, pid} -> GenServer.call(pid, call, timeout)
                  #  _ -> :error
                  #end # end case
                  :error
            end



        end # end try
      end # end s_call

      def s_cast(worker, call) do
        worker = normid(worker)
        try do
          case get_pid(worker) do
            {:ok, pid} -> GenServer.cast(pid, call)
            _ -> :error
          end
        catch
          :exit, e ->
            case e do
              {:timeout, c} ->
                Logger.info "#{@base} - unresponsive worker (#{inspect worker}) #{inspect e}"
                :error
                _ ->
                  Logger.warn "#{@base} - dead worker (#{inspect worker})"
                  unquote(worker_lookup_handler).dereg_worker!(@base, worker)
                  #case pid_or_spawn!(worker) do
                  #  {:ok, pid} -> GenServer.cast(pid, call)
                  #  _ -> :error
                  #end # end case
                  :error
            end

        end
      end # end_rescue

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
          GenServer.cast(__MODULE__, {:load})
        end
      end # end load

      # @status
      if (unquote(only.status) && !unquote(override.status)) do

        @doc """
          Retrieve pool status
        """
        def status() do
          GenServer.call(__MODULE__, {:status}, 60_000)
        end
      end # end status

      # @generate
      if (unquote(only.generate) && !unquote(override.generate)) do

        @doc """
          Generate unique nmid value.
        """
        def generate(:nmid) do
          # Assuming uncapped sequence, and no more than 99 nodes and 999 processes per node
          GenServer.call(__MODULE__, {:generate, :nmid}, 60_000)
        end
      end # end generate

      # @add!
      if (unquote(only.add!) && !unquote(override.add!)) do
        @doc """
          Add worker pool keyed by nmid. Worker must know how to load itself, and provide a load method.
        """
        def add!(nmid) do
          GenServer.call(__MODULE__, {:add_worker, nmid}, 60_000)
        end
      end # end add!

      # @add_distributed!
      if (unquote(only.add_distributed!) && !unquote(override.add_distributed!)) do
        @doc """
          Add worker pool keyed by nmid. Worker must know how to load itself, and provide a load method.
        """
        def add_distributed!(nmid, candidates) do
          GenServer.call(__MODULE__, {:add_worker_distributed, nmid, candidates}, 60_000)
        end
      end # end add!

      # @remove!
      if (unquote(only.remove!) && !unquote(override.remove!)) do
        @doc """
          Remove worker process.
        """
        def remove!(nmid) do
          GenServer.call(__MODULE__, {:remove_worker, nmid}, 60_000)
        end
      end # end remove!

      # @fetch!
      if (unquote(only.fetch!) && !unquote(override.fetch!)) do
        @doc """
          Fetch information about worker. Exact information is class dependent.
        """
        def fetch!(nmid, details \\ :default) do
          case pid_or_spawn!(nmid) do
            {:ok, pid} -> GenServer.call(pid, {:fetch, details}, 60_000)
            _ -> :not_found
          end
        end
      end # end fetch!

      # @get_pid
      if (unquote(only.get_pid) && !unquote(override.get_pid)) do
        @doc """
          return cached pid for process or spawn if dead and return newly created pid.
        """
        def get_pid(nmid) do
          nmid = normid(nmid)
          case alive?(nmid, :worker) do
            {false, :nil} -> {:error, :not_found}
            {true, pid} -> {:ok, pid}
            error -> Logger.error "#{__MODULE__}.alive?(#{inspect nmid}) returned #{inspect error}, get_pid"
          end
        end
      end # end get_pid


      # @pid_or_spawn!
      if (unquote(only.pid_or_spawn!) && !unquote(override.pid_or_spawn!)) do
        @doc """
          return cached pid for process or spawn if dead and return newly created pid.
        """
        def pid_or_spawn!(nmid) do
          nmid = normid(nmid)
          case alive?(nmid, :worker) do
            {false, :nil} -> add!(nmid)
            {true, pid} -> {:ok, pid}
            error -> Logger.error "#{__MODULE__}.alive?(#{inspect nmid}) returned #{inspect error}, pid_or_spawn!"
          end
        end
      end # end pid_or_spawn!

      # @lookup_identifier
      if (unquote(only.lookup_identifier) && !unquote(override.lookup_identifier)) do
        @doc """
          lookup identifier to use from input tuple. If you wish to key against tuple keys simply
          implement a method that returns the passed tuple plus any format validation logic required.
        """
        def lookup_identifier(nmid) do
          raise "You must implement lookup_identifier if #{__MODULE__} callers will pass in {tuple, identifiers}."
        end
      end

      # @normid
      if (unquote(only.normid) && !unquote(override.normid)) do
        @doc """
          Normalize nmid into value used for record keeping.
        """
        def normid(nmid) when is_integer(nmid) do
          nmid
        end

        def normid(nmid) when is_bitstring(nmid) do
          nmid |> String.to_integer
        end

        def normid(nmid) when is_tuple(nmid) do
          {:ok, n} = lookup_identifier(nmid)
          n
        end
      end # end normid


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

        def add!(rnode, nmid, :asynch) do
          GenServer.cast({__MODULE__, rnode}, {:add_worker, nmid})
        end
      end # end add!

      # @migrate!
      if (unquote(only.migrate!) && !unquote(override.migrate!)) do
        def migrate!(nmid, rnode, :asynch) do
          if Node.ping(rnode) == :pong do
            case alive?(nmid, :worker) do
              {false, :nil} ->
                # Call Server to spawn worker and then fetch results.
                push_migrate(nmid, rnode, :asynch)
              {true, pid} ->
                # Call worker directly
                GenServer.cast(pid, {:begin_migrate_worker, nmid, rnode})
            end
          else
            {:error, {:node, :unreachable}}
          end
        end

        def migrate!(nmid, rnode) do
          if Node.ping(rnode) == :pong do
            case alive?(nmid, :worker) do
              {false, :nil} ->
                # Call Server to spawn worker and then fetch results.
                push_migrate(nmid, rnode)
              {true, pid} ->
                # Call worker directly
                GenServer.call(pid, {:begin_migrate_worker, nmid, rnode}, 200_000)
            end
          else
            {:error, {:node, :unreachable}}
          end
        end
      end # end migrate!

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
              s_cast(pid, {:fetch, nmid, details, caller})
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

        def alive?(nmid, :worker) do
          nmid = normid(nmid)
          unquote(worker_lookup_handler).get_reg_worker!(@base, nmid)
        end
      end # end alive?

      def worker_lookup() do
        unquote(worker_lookup_handler)
      end

        #-----------------------------------------------------------------------------
        # add/3
        #-----------------------------------------------------------------------------
      # @add
      if (unquote(only.add) && !unquote(override.add)) do
        def add(nmid, :worker, sup) do
          case alive?(nmid, :worker) do
              {:false, :nil} -> start(nmid, :worker, @worker_supervisor)
              {:true, pid} -> {:ok, pid}
              error -> Logger.error "#{__MODULE__}.alive?(#{inspect nmid}) returned #{inspect error}, add"
          end
        end
      end # end add

      # @add
      if (unquote(only.add_distributed) && !unquote(override.add_distributed)) do
        def add_distributed(nmid, candidates, :worker, sup) do
          case alive?(nmid, :worker) do
              {:false, :nil} -> start_distributed(nmid, candidates, :worker, @worker_supervisor)
              {:true, pid} -> {:ok, pid}
              error -> Logger.error "#{__MODULE__}.alive?(#{inspect nmid}) returned #{inspect error}, add"
          end
        end
      end # end add

        #-----------------------------------------------------------------------------
        # start_distributed/5
        #-----------------------------------------------------------------------------
      if (unquote(only.start_distributed) && !unquote(override.start_distributed)) do
        def start_distributed(nmid, candidates, :worker, sup) do
          nmid = normid(nmid)
          current = node()
          {proceed, response} = List.foldl(candidates, {true, {:error, :no_valid_node}},
            fn(x, {proceed, response}) ->
              if proceed do

                if Node.ping(x) == :pong do
                  init = if (x == current) do
                    childSpec = @worker_supervisor.child(nmid)
                    Supervisor.start_child(@worker_supervisor, childSpec)
                  else
                    GenServer.call({__MODULE__, x}, {:start, nmid}, 60_000)
                  end

                  case init do
                    {:ok, pid} ->
                      #reg_worker(nmid, pid)
                      {false, {:ok, pid}}
                    {:error, {:already_started, pid}} ->
                      #reg_worker(nmid, pid)
                      {false, {:ok, pid}}
                    error ->
                      Logger.error "
                      *********************************************************
                      * #{__MODULE__} #{inspect nmid}  Start Distributed Failed Start: #{inspect error}
                      *********************************************************
                      "
                      {proceed, error}
                  end
                else  # else == :pong
                  {proceed, response}
                end # end if else ping


              else # else if processed
                {proceed, response}
              end # end if else processed
            end # end List.foldl cn
          )
          response
        end
      end

      #-----------------------------------------------------------------------------
      # handle_call_start
      #-----------------------------------------------------------------------------
      if (unquote(only.handle_call_start) && !unquote(override.handle_call_start)) do
        def handle_call({:start, identifier}, _from, state) do
          {:reply, start(identifier, :worker, @worker_supervisor), state}
        end

        def handle_cast({:start, identifier}, state) do
          start(identifier, :worker, @worker_supervisor)
          {:noreply, state}
        end
      end

      #-----------------------------------------------------------------------------
      # push_migrate
      #-----------------------------------------------------------------------------
      if (unquote(only.push_migrate) && !unquote(override.push_migrate)) do
        def push_migrate(transfer, rnode) do
          if Node.ping(rnode) == :pong do
            GenServer.call({__MODULE__, rnode}, {:start, transfer}, 200_000)
          else
            {:error, {:node, :unreachable}}
          end
        end

        def push_migrate(transfer, rnode, :asynch) do
          if Node.ping(rnode) == :pong do
            GenServer.cast({__MODULE__, rnode}, {:start, transfer}, 200_000)
          else
            {:error, {:node, :unreachable}}
          end
        end
      end

      #-----------------------------------------------------------------------------
      # start/4, start/3
      #-----------------------------------------------------------------------------
      if (unquote(only.start) && !unquote(override.start)) do
        def start({:migrate, nmid, _state} = transfer, :worker, sup) do
          childSpec = @worker_supervisor.child(nmid, transfer)
          case Supervisor.start_child(@worker_supervisor, childSpec) do
            {:ok, pid} ->
              #reg_worker(nmid, pid)
              {:ok, pid}
            {:error, {:already_started, pid}} ->
              #reg_worker(nmid, pid)
              {:ok, pid}

            {:error, :already_present} ->
                # We may no longer simply restart child as it may have been initilized
                # With transfer_state and must be restarted with the correct context.
                Supervisor.delete_child(@worker_supervisor, nmid)
                case Supervisor.start_child(@worker_supervisor, childSpec) do
                  {:ok, pid} -> {:ok, pid}
                  error -> error
                end

            error ->
              Logger.warn("#{__MODULE__} unable to start #{inspect nmid}")
              error
          end # end case
        end # end def

        def start(nmid, :worker, sup) when is_number(nmid) or is_tuple(nmid) or is_bitstring(nmid) do
          nmid = normid(nmid)
          childSpec = @worker_supervisor.child(nmid)
          case Supervisor.start_child(@worker_supervisor, childSpec) do
            {:ok, pid} ->
              #reg_worker(nmid, pid)
              {:ok, pid}

            {:error, {:already_started, pid}} ->
              #reg_worker(nmid, pid)
              {:ok, pid}


          {:error, :already_present} ->
              # We may no longer simply restart child as it may have been initilized
              # With transfer_state and must be restarted with the correct context.
              Supervisor.delete_child(@worker_supervisor, nmid)
              case Supervisor.start_child(@worker_supervisor, childSpec) do
                {:ok, pid} -> {:ok, pid}
                error -> error
              end

            error ->
              #Logger.warn("#{__MODULE__} unable to start #{inspect nmid}")
              error
          end # end case
        end # end def

        def start(nmid, arguments, :worker, sup) when is_number(nmid) or is_tuple(nmid) do
          childSpec = @worker_supervisor.child(nmid, arguments)
          case Supervisor.start_child(@worker_supervisor, childSpec) do
            {:ok, pid} ->
              {:ok, pid}
            {:error, {:already_started, pid}} ->
              {:ok, pid}
            error ->
              Logger.warn("#{__MODULE__} unable to start #{inspect nmid}\n(#{inspect error})")
              error
          end
        end

        def start(nmid, arguments, :worker, sup) when is_bitstring(nmid) do
          start(nmid |> Integer.parse() |> elem(0), arguments, :worker, @worker_supervisor)
        end
      end # end start

        #-----------------------------------------------------------------------------
        # remove/3
        #-----------------------------------------------------------------------------

        # @remove
        if (unquote(only.remove) && !unquote(override.remove)) do
        def remove(nmid, :worker, sup) when is_number(nmid) or is_tuple(nmid) do
          Supervisor.terminate_child(@worker_supervisor, nmid)
          Supervisor.delete_child(@worker_supervisor, nmid)
          #dereg_worker(nmid)
        end
        def remove(nmid, :worker, sup) when is_bitstring(nmid) do
          remove(nmid |> Integer.parse() |> elem(0), :worker, @worker_supervisor)
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

      # @call_generate
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
          response = add(nmid, :worker, @worker_supervisor)
          {:reply, response, state}
        end

        def handle_cast({:add_worker, nmid}, %Noizu.SimplePool.Server.State{pool: sup} = state) do
          # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
          spawn fn() -> add(nmid, :worker, @worker_supervisor) end
          {:noreply, state}
        end
      end # end call_add_worker


      # @call_add_worker
      if (unquote(only.call_add_worker_distributed) && !unquote(override.call_add_worker_distributed)) do
        def handle_call({:add_worker_distributed, nmid, candidates}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
          # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
          response = add_distributed(nmid, candidates, :worker, @worker_supervisor)
          {:reply, response, state}
        end

        def handle_cast({:add_worker_distributed, nmid, candidates}, %Noizu.SimplePool.Server.State{pool: sup} = state) do
          # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
          spawn fn() -> add_distributed(nmid, candidates, :worker, @worker_supervisor) end
          {:noreply, state}
        end
      end # end call_add_worker

      # @call_remove_worker
      if (unquote(only.call_remove_worker) && !unquote(override.call_remove_worker)) do
        def handle_call({:remove_worker, nmid}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
          # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
          response = remove(nmid, :worker, @worker_supervisor)
          {:reply, response, state}
        end

        def handle_cast({:remove_worker, nmid}, %Noizu.SimplePool.Server.State{pool: sup} = state) do
          # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
          remove(nmid, :worker, @worker_supervisor)
          {:noreply, state}
        end
      end # end call_remove_worker

      # @call_fetch
      if (unquote(only.call_fetch) && !unquote(override.call_fetch)) do
        def handle_call({:fetch, nmid, details}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
              {:ok, pid} = add(nmid, :worker, @worker_supervisor)
              response = s_call(pid, {:fetch, details})
              {:reply, response, state}
        end
      end # end call_fetch

        #=========================================================================
        #=========================================================================
        # Common Cast Handlers for SimpleServer
        #=========================================================================
        #=========================================================================

      # @cast_load
      if (unquote(only.cast_load) && !unquote(override.cast_load)) do

        if (!unquote(asynch_load)) do
          def handle_cast({:load}, state) do
            Logger.info "INITIAL LOAD: #{inspect state}"
            {:noreply, state}
          end
        end

        if (unquote(asynch_load)) do
          def handle_cast({:load}, %Noizu.SimplePool.Server.State{status: status} = state) do
            if status == :uninitialized do
              state = %Noizu.SimplePool.Server.State{state| status: :initializing}

              spawn fn ->
                {status, details} = lazy_load(state)
                GenServer.call(__MODULE__, {:load_complete, {status, details}}, 60_000)
              end

              {:noreply, state}
            else
              {:noreply, state}
            end
          end
        end
      end # end cast_load
      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
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
