defmodule Noizu.SimplePool.WorkerSupervisorBehaviour do
  #@callback tests() :: :ok
  defmacro __using__(options) do
    max_restarts = Dict.get(options, :max_restarts, 100)
    max_seconds = Dict.get(options, :max_seconds, 5)
    strategy = Dict.get(options, :strategy, :one_for_one)
    global_verbose = Dict.get(options, :verbose, false)
    module_verbose = Dict.get(options, :worker_supervisor_verbose, false)


    quote do
      #@behaviour Noizu.SimplePool.WorkerSupervisorBehaviour
      @before_compile unquote(__MODULE__)
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
      @worker Module.concat([@base, "Worker"])
      @test_attribute :sentinel
      use Supervisor
      import unquote(__MODULE__)

      def start_link do
        if (unquote(global_verbose) || unquote(module_verbose)) do
          "************************************************\n" <>
          "* START_LINK #{__MODULE__} ()\n" <>
          "************************************************\n" |> IO.puts()
        end
        Supervisor.start_link(__MODULE__, [], [{:name, __MODULE__}])
      end

      def child(nmid) do
        worker(@worker, [nmid], [id: nmid])
      end

      def child(id, params) do
        worker(@worker, [params], [id: id])
      end

      def init(any) do
        if (unquote(global_verbose) || unquote(module_verbose)) do
          "************************************************\n" <>
          "* INIT #{__MODULE__} (#{inspect any })\n" <>
          "************************************************\n" |> IO.puts()
        end
        supervise([], [{:strategy, unquote(strategy)}, {:max_restarts, unquote(max_restarts)}, {:max_seconds, unquote(max_seconds)}])
      end
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
    end # end quote
  end # end __before_compile__


end
