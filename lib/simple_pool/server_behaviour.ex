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
              #=========================================================================
              # Common Cast Handlers for SimpleServer
              #=========================================================================
              #=========================================================================
                # @TODO bring in dependency on or merge with scaffolding to expose CallingContext entities.
                # @TODO convience methods for comunicating with workers.
                # @TODO auto generate convience methods, fetch worker_entity_provider\s set of methods using reflection. and use macros to genrate.
                @callback fetch_worker!(identifier :: any, sychronous :: boolean) :: :not_yet_defined # worker pid, success indifcator, worker ref, etc.


                  def worker_lookup() do
                    unquote(worker_lookup_handler)
                  end





                  # todo thes belong back iun server - but can assume ref provided
                  # @TODO start_child, remove_child to differentiate from  worker_add, worker_remove which contain additional steps to communicate with underlying entity.
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

                        def remove(nmid, :worker, sup) when is_number(nmid) or is_tuple(nmid) do
                          Supervisor.terminate_child(sup, nmid)
                          Supervisor.delete_child(sup, nmid)
                          #dereg_worker(nmid)
                        end

                        def remove(nmid, :worker, sup) when is_bitstring(nmid) do
                          remove(nmid |> Integer.parse() |> elem(0), :worker, sup)
                        end







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
