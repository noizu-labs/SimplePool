defmodule Noizu.SimplePool.Behaviour do
  require Logger

  @callback nmid_seed() :: {integer, integer}
  @callback lookup_table() :: atom
  @callback book_keeping_init() :: {{integer, integer}, integer}
  @callback generate_nmid(Noizu.SimplePool.Server.State.t) :: {integer, Noizu.SimplePool.Server.State.t}

  @features([:auto_increment])
  @default_features([:auto_increment])
  @modules([:worker, :server, :worker_supervisor, :pool_supervisor])
  @default_modules([:worker_supervisor, :pool_supervisor])
  @methods([:lookup_table, :book_keeping_init, :generate_nmid])

  @options(
    features: %{default: @default_features, available: @features},
    disable:  %{default: [], available: @features},
    only:     %{default: @methods, available: @methods},
    override: %{default: [], available: @methods},
    default:  %{default: @default_modules, available: @modules},
    verbose:  %{default: Application.get_env(Noizu.SimplePool, :verbose, false)}
  )

  def simple_nmid({node, process}, sequence), do: (node + (process * 100) + (sequence * 1000000))

  def prepare_options(options, settings) do
    List.foldl(
      Keyword.keys(options),
      %{},
      fn(key, acc) ->
        if Map.has_key?(settings, key) do
          expanded = prepare_option(key, options, settings[key])
          Map.put(options, key, expanded)
        else
          Logger.warn("Unknown use option #{inspect key} passed to #{__MODULE__}")
        end
      end
    )
  end

  def prepare_option(key, options, %{default: default, available: available}) do
    arg = Keyword.get(options, key, default)
    expanded = List.foldl(available, %{}, fn(method, acc) -> Map.put(acc, method, Enum.member?(arg, method)) end)
    case List.foldl(arg, [], &(if !Enum.member?(available, &1), do: &2 ++ [x], else: &2)) do
      [] -> :ok
      l -> Logger.warn("Invalid use parameter passed to #{__MODULE__} for option #{key}. #{inspect l} not in supported list #{inspect available}")
    end
    expanded
  end

  def prepare_option(key, options, %{default: default}) do
    Keyword.get(options, key, default)
  end

  defmacro __using__(options) do
    expanded_options = prepare_options(options, @options)

    # Submodule Options
    worker_options = if (default?.worker) do
      options
      |> Keyword.get(:worker_options, @default_options[]) |> Keyword.put(:verbose, global_verbose)
    else

    end


    server_options = Keyword.get(options, :server_options, []) |> Keyword.put(:verbose, global_verbose)
    worker_supervisor_options = Keyword.get(options, :worker_supervisor_options, []) |> Keyword.put(:verbose, global_verbose)
    pool_supervisor_options = Keyword.get(options, :pool_supervisor_options, []) |> Keyword.put(:verbose, global_verbose)

    nmid_table = Keyword.get(options, :nmid_table)
    if nmid_table == nil && require?.generate_nmid do
       raise "NMID_TABLE must be set to environments NMID Generator Table"
    end



    quote do
      require Amnesia
      require Amnesia.Fragment
      require Amnesia.Helper
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.Behaviour

      def nmid_seed(), do: {nil, nil}

      if (!unquote(disable_lookup_table)) do
        @lookup_table Module.concat([__MODULE__, "LookupTable"])
        def lookup_table() do
          @lookup_table
        end
      end

      if (!unquote(disable_generate_nmid)) do
        def generate_nmid(%Noizu.SimplePool.Server.State{nmid_generator: {{node, process}, sequence}} = state) do
          sequence = sequence + 1
          nmid = simple_nmid({node, process}, sequence)

          Amnesia.Fragment.transaction do
            %unquote(nmid_table){
              handle: {node, process},
              sequence: sequence
            } |> unquote(nmid_table).write
          end

          # TODO - Update Mnesia - # Todo setup master nmid coordinator. Processes just ask it to assign a sequence, and identifier.
          state = %Noizu.SimplePool.Server.State{state| nmid_generator: {{node, process}, sequence} }
          {nmid, state}
        end
      end

      if (!unquote(disable_book_keeping_init)) do
        @doc """
          Setup ETS record keeping table.
        """
        def book_keeping_init() do
          if (unquote(global_verbose) || unquote(module_verbose)) do
            "************************************************\n" <>
            "* BOOK_KEEPING: #{__MODULE__}\n" <>
            "************************************************\n" |> IO.puts()
          end

          nmid_seed = __MODULE__.nmid_seed()
          ets_table = __MODULE__.lookup_table()

          # Load sequence from mnesia for nmid generator.
          entry = Amnesia.Fragment.transaction do
            unquote(nmid_table).read(nmid_seed)
          end

          sequence = case entry do
            %unquote(nmid_table){sequence: s} -> s
            :nil -> 1
          end

          # Start Ets Lookup Table for Worker book keeping.
          :ets.new(ets_table, [:public, :named_table, :set, read_concurrency: true])

          # Return Sequence Information
          {nmid_seed, sequence}
        end
      end

      if (unquote(default_worker)) do
        defmodule Worker do
          use Noizu.SimplePool.WorkerBehaviour, unquote(worker_options)
        end
      end

      if (unquote(default_server)) do
        defmodule Server do
          use Noizu.SimplePool.ServerBehaviour, unquote(server_options)
          def lazy_load(state), do: state
        end
      end

      if (unquote(default_worker_supervisor)) do
        defmodule WorkerSupervisor do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(worker_supervisor_options)
        end
      end

      if (unquote(default_pool_supervisor)) do
        defmodule PoolSupervisor do
          use Noizu.SimplePool.PoolSupervisorBehaviour, unquote(pool_supervisor_options)
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
