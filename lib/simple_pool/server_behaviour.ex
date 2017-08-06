defmodule Noizu.SimplePool.ServerBehaviour do
  @callback option_settings() :: Map.t
  @callback start_link() :: any
  @callback start_children(any) :: any

  @methods([])
  @features([:auto_identifier, :lazy_load, :inactivitiy_check, :s_redirect])
  @default_features([:lazy_load, :s_redirect, :inactivity_check])

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        features: %OptionList{option: :features, default: Application.get_env(Noizu.SimplePool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: Application.get_env(Noizu.SimplePool, :verbose, false)},
        worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
        server_driver: %OptionValue{option: :server_driver, default:Application.get_env(Noizu.SimplePool, :default_server_driver, Noizu.SimplePool.ServerDriver.Default)},
        worker_lookup_handler: %OptionValue{option: :worker_lookup_handler, default: Application.get_env(Noizu.SimplePool, :worker_lookup_handler, Noizu.SimplePool.WorkerLookupBehaviour)},
      }
    }

    initial = OptionSettings.expand(settings, options)
    modifications = Map.put(initial.effective_options, :required, List.foldl(@methods, %{}, fn(x, acc) -> Map.put(acc, x, initial.effective_options.only[x] && !initial.effective_options.override[x]) end))
    %OptionSettings{initial| effective_options: Map.merge(initial.effective_options, modifications)}
  end

  defmacro __using__(options) do
    option_settings = prepare_options(options)
    options = option_settings.effective_options
    required = options.required
    verbose = options.verbose
    worker_lookup_handler = options.worker_lookup_handler

    #-----------------------------------------------------------------------------
    # Refactoring . . .
    #-----------------------------------------------------------------------------
    #asynch_load = Keyword.get(options, :asynch_load, false)
    #distributed? = Keyword.get(options, :user_distributed_calls, false)
    #-----------------------------------------------------------------------------
    # . . . . Refactoring
    #-----------------------------------------------------------------------------
    quote do
      require Logger
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.ServerBehaviour
      @base(Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat)

      @worker(Module.concat([@base, "Worker"]))
      @worker_supervisor(Module.concat([@base, "WorkerSupervisor"]))
      @server(__MODULE__)
      @pool_supervisor(Module.concat([@base, "PoolSupervisor"]))
      @simple_pool_group({@base, @worker, @worker_supervisor, __MODULE__, @pool_supervisor})

      @worker_state_entity(Noizu.SimplePool.Behaviour.expand_worker_state_entity(@base, unquote(options.worker_state_entity)))
      @server_provider(unquote(options.server_provider))
      @worker_lookup_handler(unquote(worker_lookup_handler))

      def option_settings do
        unquote(Macro.escape(option_settings))
      end

      #=========================================================================
      # Genserver Lifecycle
      #=========================================================================
      if unquote(required.start_link) do
        def start_link(sup) do
          if unquote(verbose) do
            @base.banner("START_LINK #{__MODULE__} (#{inspect sup})") |> IO.puts()
          end
          GenServer.start_link(__MODULE__, sup, name: __MODULE__)
        end
      end # end start_link

      # @init
      if (unquote(required.init)) do
        def init(sup) do
          if unquote(verbose) do
            @base.banner("INIT #{__MODULE__} (#{inspect sup})") |> IO.puts()
          end
          @server_provider.init(@simple_pool_group, option_settings())
        end
      end # end init

      # @terminate
      if (unquote(required.terminate)) do
        def terminate(reason, state), do: @server_provider.terminate(state)
      end # end terminate

      #=========================================================================
      #  Common Convienence Methods
      #=========================================================================
      if unquote(required.load) do
        @doc "Load pool from datastore."
        def load(), do: GenServer.cast(__MODULE__, {:load})
      end # end load

      if unquote(required.status) do
        @doc "Retrieve pool status"
        def status(), do: GenServer.call(__MODULE__, {:status})
      end # end status

      if unquote(required.add!) do
        @doc "Add worker pool keyed by nmid. Worker must know how to load itself, and provide a load method."
        def add!(identifier), do: GenServer.call(__MODULE__, {:add_worker, identifier})
      end # end add!

      if unquote(required.remove!) do
        @doc "Remove worker process."
        def remove!(identifier), do: GenServer.call(__MODULE__, {:remove_worker, identifier})
      end # end remove!

      if unquote(required.fetch!) do
        @doc "Fetch information about worker. Exact information is class dependent."
        def fetch!(identifier, details \\ :default), do: s_call!(identifier, {:fetch, details})
      end # end fetch!

      if unquote(required.get_pid) do
        @doc "return cached pid for process or spawn if dead and return newly created pid."
        def get_pid(nmid) do
          nmid = normid(nmid)
          case alive?(nmid, :worker) do
            {false, :nil} -> {:error, :not_found}
            {true, pid} -> {:ok, pid}
            error -> Logger.error "#{__MODULE__}.alive?(#{inspect nmid}) returned #{inspect error}, get_pid"
          end
        end
      end # end get_pid

      if unquote(required.pid_or_spawn!) do
        @doc "return cached pid for process or spawn if dead and return newly created pid."
        def pid_or_spawn!(nmid) do
          nmid = normid(nmid)
          case alive?(nmid, :worker) do
            {false, :nil} -> add!(nmid)
            {true, pid} -> {:ok, pid}
            error -> Logger.error "#{__MODULE__}.alive?(#{inspect nmid}) returned #{inspect error}, pid_or_spawn!"
          end
        end
      end # end pid_or_spawn!







                  # @remove!
                  if unquote(required.remove!) do

                    @doc """
                      Remove worker Asynch
                    """
                    def remove!(nmid, :asynch) do
                      GenServer.cast(__MODULE__, {:remove_worker, nmid})
                    end
                  end # end remove!

                  # @add!
                  if unquote(required.add!) do

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

                  # @fetch!
                  if unquote(required.fetch!) do

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
                  if unquote(required.alive?) do

                    #-----------------------------------------------------------------------------
                    # alive/2
                    #-----------------------------------------------------------------------------
                    def alive?(:nil, :worker) do
                      {false, :nil}
                    end

                    def alive?(nmid, :worker) when is_number(nmid) or is_tuple(nmid) or is_bitstring(nmid) do
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
                  if unquote(required.add) do
                    def add(nmid, :worker, sup) do
                      case alive?(nmid, :worker) do
                          {:false, :nil} -> start(nmid, :worker, sup)
                          {:true, pid} -> {:ok, pid}
                          error -> Logger.error "#{__MODULE__}.alive?(#{inspect nmid}) returned #{inspect error}, add"
                      end
                    end
                  end # end add



      #-----------------------------------------------------------------------------
      # Refactoring . . .
      #-----------------------------------------------------------------------------
      if unquote(required.lookup_identifier) do
        @doc """
          lookup identifier to use from input tuple. If you wish to key against tuple keys simply
          implement a method that returns the passed tuple plus any format validation logic required.
          @TODO -> use ref, use features to determine if a cached lookup table will be used for mapping from say serials to appengine ids.
        """
        def lookup_identifier(nmid) do
          raise "You must implement lookup_identifier if #{__MODULE__} callers will pass in {tuple, identifiers}."
        end
      end

      # @TODO - move into auto_increment feature
      if unquote(required.next_sequencer_id) do
        @doc "Generate unique nmid value."
        def next_sequencer_id(), do: GenServer.call(__MODULE__, {:next_sequencer_id})
      end # end generate

      if unquote(required.normid) do
        @doc "Normalize nmid into value used for record keeping."
        def normid(nmid) when is_integer(nmid), do: nmid
        def normid(nmid) when is_bitstring(nmid), do: nmid |> String.to_integer
        def normid(nmid) when is_tuple(nmid) do
          {:ok, n} = lookup_identifier(nmid)
          n
        end
      end # end normid

      #-----------------------------------------------------------------------------
      # . . . . Refactoring
      #-----------------------------------------------------------------------------

              #-----------------------------------------------------------------------------
              # start/3
              #-----------------------------------------------------------------------------
            # @start
            if unquote(required.start) do
              def start(nmid, :worker, sup) when is_number(nmid) or is_tuple(nmid) or is_bitstring(nmid) do
                nmid = normid(nmid)
                childSpec = @worker_supervisor.child(nmid)
                case Supervisor.start_child(sup, childSpec) do
                  {:ok, pid} ->
                    #reg_worker(nmid, pid)
                    {:ok, pid}

                  {:error, {:already_started, pid}} ->
                    #reg_worker(nmid, pid)
                    {:ok, pid}
                  error ->
                    #Logger.warn("#{__MODULE__} unable to start #{inspect nmid}")
                    error
                end # end case
              end # end def
            end # end start

              #-----------------------------------------------------------------------------
              # start/4
              #-----------------------------------------------------------------------------
              # @start
              if unquote(required.start) do
              def start(nmid, arguments, :worker, sup) when is_number(nmid) or is_tuple(nmid) do
                childSpec = @worker_supervisor.child(nmid, arguments)
                case Supervisor.start_child(sup, childSpec) do
                  {:ok, pid} ->
                    {:ok, pid}
                  {:error, {:already_started, pid}} ->
                    {:ok, pid}
                  error ->
                    IO.puts("#{__MODULE__} unable to start #{inspect nmid}")
                    error
                end
              end

              def start(nmid, arguments, :worker, sup) when is_bitstring(nmid) do
                start(nmid |> Integer.parse() |> elem(0), arguments, :worker, sup)
              end
            end # end start

              #-----------------------------------------------------------------------------
              # remove/3
              #-----------------------------------------------------------------------------

              # @remove
              if unquote(required.remove) do
              def remove(nmid, :worker, sup) when is_number(nmid) or is_tuple(nmid) do
                Supervisor.terminate_child(sup, nmid)
                Supervisor.delete_child(sup, nmid)
                #dereg_worker(nmid)
              end
              def remove(nmid, :worker, sup) when is_bitstring(nmid) do
                remove(nmid |> Integer.parse() |> elem(0), :worker, sup)
              end

            end # end remove

            # @worker_pid!
            if unquote(required.worker_pid!) do


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
            if unquote(required.call_load_complete) do
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
            if unquote(required.call_status) do
              def handle_call({:status}, _from, %Noizu.SimplePool.Server.State{status: status} = state) do
                {:reply, status, state}
              end
            end # end call_status

            # @call_generate
            if unquote(required.call_generate) do
              def handle_call({:generate, :nmid}, _from, %Noizu.SimplePool.Server.State{nmid_generator: {{node, process}, sequence}} = state) do
                {nmid, state} = @base.generate_nmid(state)
                {:reply, nmid, state}
              end
            end # end call_generate

            # @call_add_worker
            if unquote(required.call_add_worker) do
              def handle_call({:add_worker, nmid}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
                # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
                response = add(nmid, :worker, sup)
                {:reply, response, state}
              end

              def handle_cast({:add_worker, nmid}, %Noizu.SimplePool.Server.State{pool: sup} = state) do
                # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
                spawn fn() -> add(nmid, :worker, sup) end
                {:noreply, state}
              end
            end # end call_add_worker

            # @call_remove_worker
            if unquote(required.call_remove_worker) do
              def handle_call({:remove_worker, nmid}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
                # Check if existing entry exists. If so confirm it is live and return {:exists, pid} or respawn
                response = remove(nmid, :worker, sup)
                {:reply, response, state}
              end
            end # end call_remove_worker

            # @call_fetch
            if unquote(required.call_fetch) do
              def handle_call({:fetch, nmid, details}, _from, %Noizu.SimplePool.Server.State{pool: sup} = state) do
                    {:ok, pid} = add(nmid, :worker, sup)
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
            if unquote(required.cast_load) do

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
            end # end cast_load

            # @s_redirect
            if unquote(MapSet.member?(features, :s_redirect)) do
              def handle_cast({:s_cast, {mod, nmid}, call}, state) do
                if (mod == @base) do
                  handle_cast(call, state)
                else
                  __MODULE__.worker_lookup().clear_process!(mod, nmid, {self(), node})
                  server = Module.concat(mod, "Server")
                  server.s_cast(nmid, call)
                  {:noreply, state}
                end
              end # end handle_cast/:s_cast

              def handle_cast({:s_cast!, {mod, nmid}, call}, state) do
                if (mod == @base) do
                  handle_cast(call, state)
                else
                  __MODULE__.worker_lookup().clear_process!(mod, nmid, {self(), node})
                  server = Module.concat(mod, "Server")
                  server.s_cast!(nmid, call)
                  {:noreply, state}
                end
              end # end handle_cast/:s_cast!

              def handle_call({:s_call, {mod, nmid, time_out}, call}, from, state) do
                if (mod == @base) do
                  handle_call(call, from, state)
                else
                  __MODULE__.worker_lookup().clear_process!(mod, nmid, {self(), node})
                  {:reply, :s_retry, state}
                end
              end # end handle_call/:s_call

              def handle_call({:s_call!, {mod, nmid, time_out}, call}, from, state) do
                if (mod == @base) do
                  handle_call(call, from, state)
                else
                  __MODULE__.worker_lookup().clear_process!(mod, nmid, {self(), node})
                  {:reply, :s_retry, state}
                end
              end # end handle_call/:s_call!
            end # end s_redirect















      #=========================================================================
      # s_call -
      # @note I am resisting the urge to move implementation into the parent
      # module for sake of faster execution speed at the cost of a little compile time.
      #=========================================================================

      if unquote(MapSet.member?(features, :crash_protection)) do
        #-----------------------------------------------------------------------
        # s_call! - crash protection
        #-----------------------------------------------------------------------
        def s_call!(worker, call, timeout \\ 15_000) do
          worker = normid(worker)
          redirect_call = if unquote(MapSet.member?(features, :s_redirect)), do: {:s_call!, {@base, worker, timeout}, call}, else: call
          try do
            case pid_or_spawn!(worker) do
              {:ok, pid} ->
                case GenServer.call(pid, redirect_call, timeout) do
                  :s_retry ->
                    case pid_or_spawn!(worker) do
                      {:ok, pid} -> GenServer.call(pid, redirect_call, timeout)
                      error -> error
                    end
                  v -> v
                end
              error -> error
            end # end case
          catch
            :exit, e ->
              Logger.warn "#{@base} - dead worker (#{inspect worker})"
              unquote(worker_lookup_handler).dereg_worker!(@base, worker)
              case pid_or_spawn!(worker) do
                {:ok, pid} ->
                  case GenServer.call(pid, redirect_call, timeout) do
                    :s_retry ->
                      case pid_or_spawn!(worker) do
                        {:ok, pid} -> GenServer.call(pid, redirect_call, timeout)
                        error -> error
                      end
                    v -> v
                  end
                error -> error
              end  # end case
          end # end try
        end # end s_call!

        #-----------------------------------------------------------------------
        # s_cast! - crash protection
        #-----------------------------------------------------------------------
        def s_cast!(worker, call) do
          worker = normid(worker)
          redirect_call = if unquote(MapSet.member?(features, :s_redirect)), do: {:s_cast!, {@base, worker}, call}, else: call
          try do
            case pid_or_spawn!(worker) do
              {:ok, pid} -> GenServer.cast(pid, redirect_call)
              error -> error
            end
          catch
            :exit, e ->
              Logger.warn "#{@base} - dead worker (#{inspect worker})"
              unquote(worker_lookup_handler).dereg_worker!(@base, worker)
              case pid_or_spawn!(worker) do
                {:ok, pid} -> GenServer.cast(pid, redirect_call)
                error -> error
              end # end case
          end # end try
        end # end s_cast!

        #-----------------------------------------------------------------------
        # s_call - crash protection
        #-----------------------------------------------------------------------
        def s_call(worker, call, timeout \\ 15_000) do
          worker = normid(worker)
          redirect_call = if unquote(MapSet.member?(features, :s_redirect)), do: {:s_call, {@base, worker, timeout}, call}, else: call
          try do
            case get_pid(worker) do
              {:ok, pid} ->
                case GenServer.call(pid, redirect_call, timeout) do
                  :s_retry ->
                    case get_pid(worker) do
                      {:ok, pid} -> GenServer.call(pid, redirect_call, timeout)
                      error -> error
                    end
                  v -> v
                end
              error -> error
            end
          catch
            :exit, e ->
              Logger.warn "#{@base} - dead worker (#{inspect worker})"
              unquote(worker_lookup_handler).dereg_worker!(@base, worker)
              case pid_or_spawn!(worker) do
                {:ok, pid} ->
                  case GenServer.call(pid, redirect_call, timeout) do
                    :s_retry ->
                      case get_pid(worker) do
                        {:ok, pid} -> GenServer.call(pid, redirect_call, timeout)
                        error -> error
                      end
                    v -> v
                  end
                error -> error
              end # end case
          end # end try
        end # end s_call

        #-----------------------------------------------------------------------
        # s_cast! - crash protection
        #-----------------------------------------------------------------------
        def s_cast(worker, call) do
          worker = normid(worker)
          redirect_call = if unquote(MapSet.member?(features, :s_redirect)), do: {:s_cast, {@base, worker}, call}, else: call
          try do
            case get_pid(worker) do
              {:ok, pid} -> IO.inspect  GenServer.cast(pid, redirect_call)
              error -> error
            end
          catch
            :exit, e ->
              Logger.warn "#{@base} - dead worker (#{inspect worker})"
              unquote(worker_lookup_handler).dereg_worker!(@base, worker)
              case pid_or_spawn!(worker) do
                {:ok, pid} -> GenServer.cast(pid, redirect_call)
                error -> error
              end
          end
        end # end_rescue

      else # no crash_protection

        #-----------------------------------------------------------------------
        # s_call! - no crash protection
        #-----------------------------------------------------------------------
        def s_call!(worker, call, timeout \\ 15_000) do
          worker = normid(worker)
          redirect_call = if unquote(MapSet.member?(features, :s_redirect)), do: {:s_call!, {@base, worker, timeout}, call}, else: call
          case pid_or_spawn!(worker) do
            {:ok, pid} ->
              case GenServer.call(pid, redirect_call, timeout) do
                :s_retry ->
                  case pid_or_spawn!(worker) do
                    {:ok, pid} -> GenServer.call(pid, redirect_call, timeout)
                    error -> error
                  end
                v -> v
              end
            error -> error
          end # end case
        end # end s_call!

        #-----------------------------------------------------------------------
        # s_cast! - no crash protection
        #-----------------------------------------------------------------------
        def s_cast!(worker, call) do
          worker = normid(worker)
          redirect_call = if unquote(MapSet.member?(features, :s_redirect)), do: {:s_cast!, {@base, worker}, call}, else: call
          case pid_or_spawn!(worker) do
            {:ok, pid} -> GenServer.cast(pid, redirect_call)
            error -> error
          end
        end # end s_cast!

        #-----------------------------------------------------------------------
        # s_call - no crash protection
        #-----------------------------------------------------------------------
        def s_call(worker, call, timeout \\ 15_000) do
          worker = normid(worker)
          redirect_call = if unquote(MapSet.member?(features, :s_redirect)), do: {:s_call, {@base, worker, timeout}, call}, else: call
          case get_pid(worker) do
            {:ok, pid} ->
              case GenServer.call(pid, redirect_call, timeout) do
                :s_retry ->
                  case get_pid(worker) do
                    {:ok, pid} -> GenServer.call(pid, redirect_call, timeout)
                    error -> error
                  end
                v -> v
              end
            error -> error
          end
        end # end s_call

        #-----------------------------------------------------------------------
        # s_cast! - no crash protection
        #-----------------------------------------------------------------------
        def s_cast(worker, call) do
          worker = normid(worker)
          redirect_call = if unquote(MapSet.member?(features, :s_redirect)), do: {:s_cast, {@base, worker}, call}, else: call
          case get_pid(worker) do
            {:ok, pid} -> IO.inspect  GenServer.cast(pid, redirect_call)
            error -> error
          end
        end # end_rescue

      end # end if feature.crash_protection


      #@before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  #defmacro __before_compile__(_env) do
  #  quote do
  #  end # end quote
  #end # end __before_compile__

end
