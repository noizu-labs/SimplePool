defmodule Noizu.SimplePool.PoolSupervisorBehaviour do
  @callback start_link() :: any
  @callback start_children(any) :: any
  @callback start_init(any) :: any

  @provided_methods [:start_link, :start_children, :init]

  defmacro __using__(options) do
    #process_identifier = Dict.get(options, :process_identifier)
    max_restarts = Dict.get(options, :max_restarts, 100)
    max_seconds = Dict.get(options, :max_seconds, 5)
    strategy = Dict.get(options, :strategy, :one_for_one)
    global_verbose = Dict.get(options, :verbose, false)
    module_verbose = Dict.get(options, :pool_supervisor_verbose, false)

    only = Noizu.SimplePool.Behaviour.map_intersect(@provided_methods, Dict.get(options, :only, @provided_methods))
    override = Noizu.SimplePool.Behaviour.map_intersect(@provided_methods, Dict.get(options, :override, []))

    quote do
      use Supervisor
      @behaviour Noizu.SimplePool.PoolSupervisorBehaviour
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
      @worker_supervisor Module.concat([@base, "WorkerSupervisor"])
      @pool_server Module.concat([@base, "Server"])
      import unquote(__MODULE__)

      # @start_link
      if (unquote(only.start_link) && !unquote(override.start_link)) do
        def start_link do
          if (unquote(global_verbose) || unquote(module_verbose)) do
            "************************************************\n" <>
            "* START_LINK #{__MODULE__}\n" <>
            "************************************************\n" |> IO.puts()
          end

          case Supervisor.start_link(__MODULE__, [], [{:name, __MODULE__}]) do
            {:ok, sup} ->
              IO.puts "#{__MODULE__}.start_link Supervisor Not Started. #{inspect sup}"
              start_children(sup)
              {:ok, sup}
            {:error, {:already_started, sup}} ->
              IO.puts "#{__MODULE__}.start_link Supervisor Already Started. Handling unexected state.  #{inspect sup}"
              #start_children(sup)
              {:ok, sup}
          end
        end
      end # end start_link

      # @start_children
      if (unquote(only.start_children) && !unquote(override.start_children)) do
        def start_children(sup) do
          if (unquote(global_verbose) || unquote(module_verbose)) do
            "----------- START_CHILDREN: ----------------------------------------------------\n" <>
            "| Options: #{inspect unquote(options)}\n"  <>
            "| #{__MODULE__}\n"  <>
            "| worker_supervisor: #{@worker_supervisor}\n"  <>
            "| worker_server: #{@pool_server}\n"  <>
            "| nmid_seed: #{inspect @base.nmid_seed()}\n"  <>
            "|===============================================================================\n" |> IO.puts()
          end

          case Supervisor.start_child(sup, supervisor(@worker_supervisor, [], [])) do
            {:ok, pool_supervisor} ->
              Supervisor.start_child(sup, worker(@pool_server, [pool_supervisor, @base.nmid_seed()], []))
            error ->
              IO.puts "#{__MODULE__}.start_children #{inspect @worker_supervisor} Already Started. Handling unexected state.
              #{inspect error}
              "
          end

          # Lazy Load Children Load Children
          GenServer.cast(@pool_server, {:load})
        end
      end # end start_children


      # @init
      if (unquote(only.init) && !unquote(override.init)) do
        def init(arg) do
          if (unquote(global_verbose) || unquote(module_verbose)) do
            "************************************************\n" <>
            "* INIT #{__MODULE__} (#{inspect arg})\n" <>
            "************************************************\n" |> IO.puts()
          end
          supervise([], [{:strategy, unquote(strategy)}, {:max_restarts, unquote(max_restarts)}, {:max_seconds, unquote(max_seconds)}])
        end
      end # end init

      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
    end # end quote
  end # end __before_compile__

end
