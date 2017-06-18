defmodule Noizu.SimplePool.Behaviour do
  @callback nmid_seed() :: {integer, integer}
  @callback lookup_table() :: atom
  @callback book_keeping_init() :: {{integer, integer}, integer}
  @callback generate_nmid(Noizu.SimplePool.Server.State.t) :: {integer, Noizu.SimplePool.Server.State.t}

  def map_intersect(list, subset) do
    List.foldl(
      list,
      %{},
      fn(entry, acc) ->
        Map.put(acc, entry, Enum.member?(subset, entry))
      end
    )
  end

  def simple_nmid({node, process}, sequence) do
    # node < 100,  0-99
    # process < 10000, 100-9999
    _nmid = (node + (process * 100) + (sequence * 1000000))
  end

  defmacro __using__(options) do
    defaults = Dict.get(options, :defaults, [])
    default_worker = Enum.member?(defaults, :worker)
    default_server = Enum.member?(defaults, :server)
    default_worker_supervisor = Enum.member?(defaults, :worker_supervisor)
    default_pool_supervisor = Enum.member?(defaults, :pool_supervisor)

    # @TODO standardize around override/only logic.
    disable = Dict.get(options, :disable, [])
    disable_lookup_table = Enum.member?(disable, :lookup_table)
    disable_book_keeping_init = Enum.member?(disable, :book_keeping_init)
    disable_generate_nmid = Enum.member?(disable, :generate_nmid)
    global_verbose = Dict.get(options, :verbose, false)
    module_verbose = Dict.get(options, :base_verbose, false)

    # @TODO copy/merge any key global options and set in worker/supervisor option set if not overriden.
    worker_options = Dict.get(options, :worker_options, [])
      |> Dict.put(:verbose, global_verbose)
    server_options = Dict.get(options, :server_options, [])
      |> Dict.put(:verbose, global_verbose)
    worker_supervisor_options = Dict.get(options, :worker_supervisor_options, [])
      |> Dict.put(:verbose, global_verbose)
    pool_supervisor_options = Dict.get(options, :pool_supervisor_options, [])
      |> Dict.put(:verbose, global_verbose)

    nmid_table = Dict.get(options, :nmid_table)
    if nmid_table == nil && !disable_generate_nmid do
       raise "NMID_TABLE must be set to environments NMID Generator Table"
    end

    quote do
      require Amnesia
      require Amnesia.Fragment
      require Amnesia.Helper
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.Behaviour

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
          def tests() do
            :ok
          end
        end
      end

      if (unquote(default_server)) do
        defmodule Server do
          use Noizu.SimplePool.ServerBehaviour, unquote(server_options)
          def lazy_load(state) do
            IO.puts "#{__MODULE__}.lazy_load Default"
            state
          end
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
