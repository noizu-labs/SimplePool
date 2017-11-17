defmodule Noizu.SimplePool.WorkerSupervisorBehaviour do
  @callback start_link() :: any
  @callback child(any) :: any
  @callback child(any, any) :: any
  @callback init(any) :: any

  @provided_methods [
      :start_link,
      :child,
      :init
  ]

  defmacro __using__(options) do
    max_restarts = Dict.get(options, :max_restarts, 3)
    max_seconds = Dict.get(options, :max_seconds, 5)
    strategy = Dict.get(options, :strategy, :one_for_one)
    global_verbose = Dict.get(options, :verbose, false)
    module_verbose = Dict.get(options, :worker_supervisor_verbose, false)
    only = Noizu.SimplePool.Behaviour.map_intersect(@provided_methods, Dict.get(options, :only, @provided_methods))
    override = Noizu.SimplePool.Behaviour.map_intersect(@provided_methods, Dict.get(options, :override, []))

    quote do
      #@behaviour Noizu.SimplePool.WorkerSupervisorBehaviour
      @before_compile unquote(__MODULE__)
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
      @worker Module.concat([@base, "Worker"])
      @test_attribute :sentinel
      use Supervisor
      import unquote(__MODULE__)
      require Logger

      # @start_link
      if (unquote(only.start_link) && !unquote(override.start_link)) do
        def start_link do
          if (unquote(global_verbose) || unquote(module_verbose)) do
            "************************************************\n" <>
            "* START_LINK #{__MODULE__} ()\n" <>
            "************************************************\n" |> IO.puts()
          end
          Supervisor.start_link(__MODULE__, [], [{:name, __MODULE__}])
        end
      end # end start_link

      # @child
      if (unquote(only.child) && !unquote(override.child)) do
        def child(nmid) do
          worker(@worker, [nmid], [id: nmid])
        end

        def child(id, params) do
          worker(@worker, [params], [id: id])
        end
      end # end child

      # @init
      if (unquote(only.init) && !unquote(override.init)) do
        def init(any) do
          if (unquote(global_verbose) || unquote(module_verbose)) do
            "************************************************\n" <>
            "* INIT #{__MODULE__} (#{inspect any })\n" <>
            "************************************************\n" |> Logger.info
          end
          supervise([], [{:strategy, unquote(strategy)}, {:max_restarts, unquote(max_restarts)}, {:max_seconds, unquote(max_seconds)}])
        end
      end # end init
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
