defmodule Noizu.SimplePool.PoolSupervisorBehaviour do
  @callback tests() :: :ok
  defmacro __using__(options) do
    #process_identifier = Dict.get(options, :process_identifier)
    max_restarts = Dict.get(options, :max_restarts, 100)
    max_seconds = Dict.get(options, :max_seconds, 5)
    strategy = Dict.get(options, :strategy, :one_for_one)
    global_verbose = Dict.get(options, :verbose, false)
    module_verbose = Dict.get(options, :pool_supervisor_verbose, false)

    quote do
      use Supervisor
      @behaviour Noizu.SimplePool.PoolSupervisorBehaviour
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
      @worker_supervisor Module.concat([@base, "WorkerSupervisor"])
      @pool_server Module.concat([@base, "Server"])
      import unquote(__MODULE__)

      def start_link do
        if (unquote(global_verbose) || unquote(module_verbose)) do
          "************************************************\n" <>
          "* START_LINK #{__MODULE__}\n" <>
          "************************************************\n" |> IO.puts()
        end
        {:ok, sup} = Supervisor.start_link(__MODULE__, [], [{:name, __MODULE__}])
        start_children(sup)
        {:ok, sup}
      end

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

        {:ok, pool_supervisor} = Supervisor.start_child(sup, supervisor(@worker_supervisor, [], []))
        Supervisor.start_child(sup, worker(@pool_server, [pool_supervisor, @base.nmid_seed()], []))

        # Lazy Load Children Load Children
        GenServer.cast(@pool_server, {:load})
      end

      def init(arg) do
        if (unquote(global_verbose) || unquote(module_verbose)) do
          "************************************************\n" <>
          "* INIT #{__MODULE__} (#{inspect arg})\n" <>
          "************************************************\n" |> IO.puts()
        end
        supervise([], [{:strategy, unquote(strategy)}, {:max_restarts, unquote(max_restarts)}, {:max_seconds, unquote(max_seconds)}])
      end

      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
    end # end quote
  end # end __before_compile__

end
