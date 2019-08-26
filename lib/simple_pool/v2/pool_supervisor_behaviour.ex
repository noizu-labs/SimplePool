#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.PoolSupervisorBehaviour do

  @moduledoc """
  PoolSupervisorBehaviour provides the implementation for the top level node in a Pools OTP tree.
  The Pool Supervisor is responsible to monitoring the ServerPool and WorkerSupervisors (which in turn monitor workers)

  @todo Implement a top level WorkerSupervisor that in turn supervises children supervisors.
  """
  @callback start_link(any, any) :: any
  @callback start_children(any, any, any) :: any

  defmodule Default do
    alias Noizu.ElixirCore.OptionSettings
    alias Noizu.ElixirCore.OptionValue
    alias Noizu.ElixirCore.OptionList
    require Logger

    @features ([:auto_load, :auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection])
    @default_features ([:auto_load, :lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection])

    @default_max_seconds (1)
    @default_max_restarts (1_000_000)
    @default_strategy (:one_for_one)

    #------------
    #
    #------------
    def prepare_options(options) do
      settings = %OptionSettings{
        option_settings: %{
          features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
          verbose: %OptionValue{option: :verbose, default: :auto},
          max_restarts: %OptionValue{option: :max_restarts, default: Application.get_env(:noizu_simple_pool, :pool_max_restarts, @default_max_restarts)},
          max_seconds: %OptionValue{option: :max_seconds, default: Application.get_env(:noizu_simple_pool, :pool_max_seconds, @default_max_seconds)},
          strategy: %OptionValue{option: :strategy, default: Application.get_env(:noizu_simple_pool, :pool_strategy, @default_strategy)}
        }
      }

      OptionSettings.expand(settings, options)
    end

    #------------
    #
    #------------
    def start_link(module, definition \\ :auto, context \\ nil) do
      if module.verbose() do
        Logger.info(fn ->
          header = "#{module}.start_link"
          body = "args: #{inspect %{definition: definition, context: context}}"
          metadata = Noizu.ElixirCore.CallingContext.metadata(context)
          {module.banner(header, body), metadata}
        end)
      end
      case Supervisor.start_link(module, [definition, context], [{:name, module}, {:restart, :permanent}]) do
        {:ok, sup} ->
          Logger.info(fn ->  {"#{module}.start_link Supervisor Not Started. #{inspect sup}", Noizu.ElixirCore.CallingContext.metadata(context)} end)
          module.start_children(sup, definition, context)
          {:ok, sup}
        {:error, {:already_started, sup}} ->
          Logger.info(fn -> {"#{module}.start_link Supervisor Already Started. Handling Unexpected State.  #{inspect sup}" , Noizu.ElixirCore.CallingContext.metadata(context)} end)
          module.start_children(sup, definition, context)
          {:ok, sup}
      end
    end

    def add_child_supervisor(module, child, definition \\ :auto, context \\ nil) do
      max_seconds = module.meta()[:max_seconds]
      max_restarts = module.meta()[:max_restarts]

      case Supervisor.start_child(module, module.pass_through_supervisor(child, [definition, context],  [name: child, restart: :permanent, max_restarts: max_restarts, max_seconds: max_seconds])) do
        {:ok, pid} ->
          {:ok, pid}
        {:error, {:already_started, process2_id}} ->
          Supervisor.restart_child(module, process2_id)
        error ->
          Logger.error(fn ->
            {
              """

              #{module}.add_child_supervisor #{inspect child} Already Started. Handling unexpected state.
              #{inspect error}
              """, Noizu.ElixirCore.CallingContext.metadata(context)}
          end)
          :error
      end
    end

    def add_child_worker(module, child, definition \\ :auto, context \\ nil) do
      max_seconds = module.meta()[:max_seconds]
      max_restarts = module.meta()[:max_restarts]

      case Supervisor.start_child(module, module.pass_through_worker(child, [definition, context],  [name: child, restart: :permanent, max_restarts: max_restarts, max_seconds: max_seconds])) do
        {:ok, pid} ->
          {:ok, pid}
        {:error, {:already_started, process2_id}} ->
          Supervisor.restart_child(module, process2_id)
        error ->
          Logger.error(fn ->
            {
              """

              #{module}.add_child_worker #{inspect child} Already Started. Handling unexpected state.
              #{inspect error}
              """, Noizu.ElixirCore.CallingContext.metadata(context)}
          end)
          :error
      end
    end

    #------------
    #
    #------------
    def start_children(module, sup, definition \\ :auto, context \\ nil) do
      if module.verbose(), do: start_children_banner(module, sup, definition, context)

      # Start Children
      {worker_supervisor_process, registry_process} =
        if (module.pool().stand_alone()) do
          {{:ok, :offline}, {:ok, :offline}}
        else
          {start_worker_supervisor_child(module, sup, definition, context),  start_registry_child(module, sup, context) }
        end



      server_process = start_server_child(module, sup, definition, context)
      monitor_process = start_monitor_child(module, sup, server_process, definition, context)

      #------------------
      # start server initilization process.
      #------------------
      if server_process != :error && module.auto_load() do
        spawn fn ->
          server = module.pool_server().load_pool(context)
        end
      end

      #------------------
      # Response
      #------------------
      outcome = cond do
        server_process == :error || Kernel.match?({:error, _}, server_process) -> :error
        monitor_process == :error || Kernel.match?({:error, _}, monitor_process) -> :error
        worker_supervisor_process == :error || Kernel.match?({:error, _}, worker_supervisor_process) -> :error
        registry_process == :error || Kernel.match?({:error, _}, registry_process) -> :error
        true -> :ok
      end


      # Return children
      children_processes = %{
        worker_supervisor_process: worker_supervisor_process,
        monitor_process: monitor_process,
        server_process: server_process,
        registry_process: registry_process
      }

      {outcome, children_processes}
    end # end start_children

    def init(module, [definition, context] = arg) do
      if module.verbose() || true do
        Logger.warn(fn -> {module.banner("#{module} INIT", "args: #{inspect arg}"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
      end
      strategy = module.meta()[:strategy]
      max_seconds = module.meta()[:max_seconds]
      max_restarts = module.meta()[:max_restarts]
      module.pass_through_supervise([], [{:strategy, strategy}, {:max_restarts, max_restarts}, {:max_seconds, max_seconds}, {:restart, :permanent}])
    end

    defp start_registry_child(module, sup, context) do
      registry_options = (module.pool().options()[:registry_options] || [])
                         |> put_in([:name], module.pool_registry())
                         |> update_in([:keys], &(&1 || :unique))
                         |> update_in([:partitions], &(&1 || 256)) # @TODO - processor count * 4


      max_seconds = module.meta()[:max_seconds]
      max_restarts = module.meta()[:max_restarts]
      #Registry.start_link(keys: :unique, name: GoldenRatio.Dispatch.AlertRegistry,  partitions: 256)
      # module.pass_through_worker(Registry, registry_options,  [restart: :permanent, max_restarts: max_restarts, max_seconds: max_seconds])
      r = case Supervisor.start_child(sup,  Registry.child_spec(registry_options)) do
        {:ok, pid} ->
          {:ok, pid}
        {:error, {:already_started, process2_id}} ->
          case Supervisor.restart_child(sup, module.pool_registry()) do
            {:error, :running} -> {:ok, process2_id}
            e -> e
          end
        error ->
          Logger.error(fn ->
            {
              """

              #{module}.start_registry_child #{inspect module.pool_registry()} Error
              #{inspect error}
              """, Noizu.ElixirCore.CallingContext.metadata(context)}
          end)
          :error
      end

      IO.puts """

      +++++++++++++++++++++++++ Registry V2 ++++++++++++++++++++++++++
      #{module.pool_registry()} -> #{inspect registry_options} - #{inspect r}}
      ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

      """

      r
    end

    defp start_worker_supervisor_child(module, sup, definition, context) do
      max_seconds = module.meta()[:max_seconds]
      max_restarts = module.meta()[:max_restarts]

      case Supervisor.start_child(sup, module.pass_through_supervisor(module.pool_worker_supervisor(), [definition, context],  [restart: :permanent, max_restarts: max_restarts, max_seconds: max_seconds])) do
        {:ok, pid} ->
          {:ok, pid}
        {:error, {:already_started, process2_id}} ->
          Supervisor.restart_child(module, process2_id)
        error ->
          Logger.error(fn ->
            {
              """

              #{module}.start_worker_supervisor_child #{inspect module.pool_worker_supervisor()} Error
              #{inspect error}
              """, Noizu.ElixirCore.CallingContext.metadata(context)}
          end)
          :error
      end
    end

    defp start_server_child(module, sup, definition, context) do
      max_seconds = module.meta()[:max_seconds]
      max_restarts = module.meta()[:max_restarts]

      case Supervisor.start_child(sup, module.pass_through_worker(module.pool_server(), [definition, context], [restart: :permanent, max_restarts: max_restarts, max_seconds: max_seconds])) do
        {:ok, pid} ->
          {:ok, pid}
        {:error, {:already_started, process2_id}} ->
          Supervisor.restart_child(module, process2_id)
        error ->
          Logger.error(fn ->
            {
              """

              #{module}.start_server_child #{inspect module.pool_server()} Error
              #{inspect error}
              """, Noizu.ElixirCore.CallingContext.metadata(context)}
          end)
          :error
      end
    end

    defp start_monitor_child(module, sup, server_process, definition, context) do
      max_seconds = module.meta()[:max_seconds]
      max_restarts = module.meta()[:max_restarts]

      case Supervisor.start_child(sup, module.pass_through_worker(module.pool_monitor(), [server_process, definition, context], [restart: :permanent, max_restarts: max_restarts, max_seconds: max_seconds])) do
        {:ok, pid} ->
          {:ok, pid}
        {:error, {:already_started, process2_id}} ->
          Supervisor.restart_child(module, process2_id)
        error ->
          Logger.error(fn ->
            {
              """

              #{module}.start_children(1) #{inspect module.pool_monitor()} Error.
              #{inspect error}
              """, Noizu.ElixirCore.CallingContext.metadata(context)}
          end)
          :error
      end
    end

    defp start_children_banner(module, sup, definition, context) do
      Logger.info(fn -> {
                          module.banner("#{module}.start_children",
                            """

                            #{module} START_CHILDREN
                            Options: #{inspect module.options()}
                            worker_supervisor: #{module.pool_worker_supervisor()}
                            worker_server: #{module.pool_server()}
                            definition: #{inspect definition}
                            """),
                          Noizu.ElixirCore.CallingContext.metadata(context)
                        }
      end)
    end

  end

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.PoolSupervisorBehaviour.Default)
    option_settings = implementation.prepare_options(options)
    options = option_settings.effective_options
    features = MapSet.new(options.features)
    message_processing_provider = Noizu.SimplePool.V2.MessageProcessingBehaviour.DefaultProvider

    quote do
      @behaviour Noizu.SimplePool.V2.PoolSupervisorBehaviour
      use Supervisor
      require Logger

      @implementation unquote(implementation)
      @parent unquote(__MODULE__)
      @module __MODULE__

      #----------------------------
      use Noizu.SimplePool.V2.SettingsBehaviour.Inherited, unquote([option_settings: option_settings])
      use unquote(message_processing_provider), unquote(option_settings)
      #--------------------------------

      @doc """
      Auto load setting for pool.
      """
      def auto_load(), do: meta()[:auto_load]

      @doc """
      start_link OTP entry point.
      """
      def start_link(definition \\ :auto, context \\ nil), do: @implementation.start_link(@module, definition, context)

      @doc """
      Start supervisor's children.
      """
      def start_children(sup, definition \\ :auto, context \\ nil), do: @implementation.start_children(@module, sup, definition, context)

      def add_child_supervisor(child, definition \\ :auto, context \\ nil), do: @implementation.add_child_supervisor(@module, child, definition, context)
      def add_child_worker(child, definition \\ :auto, context \\ nil), do: @implementation.add_child_worker(@module, child, definition, context)

      @doc """
      OTP Init entry point.
      """
      def init(arg), do: @implementation.init(@module, arg)

      #-------------------
      #
      #-------------------


      def pass_through_supervise(a,b), do: supervise(a,b)
      def pass_through_supervisor(a,b,c), do: supervisor(a,b,c)
      def pass_through_worker(a,b,c), do: worker(a,b,c)

      defoverridable [
        start_link: 2,
        start_children: 3,
        init: 1,

        add_child_supervisor: 3,
        add_child_worker: 3,

        pass_through_supervise: 2,
        pass_through_supervisor: 3,
        pass_through_worker: 3,
      ]
    end # end quote
  end #end __using__
end
