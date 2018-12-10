#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.PoolSupervisor.DefaultImplementation do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList

  require Logger
  @methods ([:start_link, :start_children, :init, :verbose, :options, :option_settings, :start_worker_supervisors])

  @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection])
  @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection])

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
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: :auto},

        implementation: %OptionValue{option: :max_restarts, default: Application.get_env(:noizu_simple_pool, :default_pool_supervisor_provider, Noizu.SimplePool.V2.PoolSupervisor.DefaultImplementation)},

        max_restarts: %OptionValue{option: :max_restarts, default: Application.get_env(:noizu_simple_pool, :pool_max_restarts, @default_max_restarts)},
        max_seconds: %OptionValue{option: :max_seconds, default: Application.get_env(:noizu_simple_pool, :pool_max_seconds, @default_max_seconds)},
        strategy: %OptionValue{option: :strategy, default: Application.get_env(:noizu_simple_pool, :pool_strategy, @default_strategy)}
      }
    }

    initial = OptionSettings.expand(settings, options)
    modifications = Map.put(initial.effective_options, :required, List.foldl(@methods, %{}, fn(x, acc) -> Map.put(acc, x, initial.effective_options.only[x] && !initial.effective_options.override[x]) end))
    %OptionSettings{initial| effective_options: Map.merge(initial.effective_options, modifications)}
  end

  #------------
  #
  #------------
  defdelegate meta(module), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  defdelegate meta(module, update), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  def meta_init(module) do
    verbose = case module.options().verbose do
      :auto -> module.pool().verbose()
      v -> v
    end
    %{
      verbose: verbose,
    }
  end

  #------------
  #
  #------------
  def pool(module), do: Module.split(module) |> Enum.slice(0..-2) |> Module.concat()
  defdelegate pool_worker_supervisor(pool), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  defdelegate pool_server(pool), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  defdelegate pool_worker(pool), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  defdelegate pool_supervisor(pool), to: Noizu.SimplePool.V2.Pool.DefaultImplementation


  #------------
  #
  #------------
  def start_link(module, context, definition \\ :auto) do
    if module.verbose() do
      Logger.info(fn ->
        header = "#{module}.start_link"
        body = "args: #{inspect %{context: context, definition: definition}}"
        metadata = Noizu.ElixirCore.CallingContext.metadata(context)
        {module.banner(header, body), metadata}
      end)
    end
    case Supervisor.start_link(module, [context], [{:name, module}, {:restart, :permanent}]) do
      {:ok, sup} ->
        Logger.info(fn ->  {"#{module}.start_link Supervisor Not Started. #{inspect sup}", Noizu.ElixirCore.CallingContext.metadata(context)} end)
        module.start_children(module, context, definition)
        {:ok, sup}
      {:error, {:already_started, sup}} ->
        Logger.info(fn -> {"#{module}.start_link Supervisor Already Started. Handling Unexpected State.  #{inspect sup}" , Noizu.ElixirCore.CallingContext.metadata(context)} end)
        module.start_children(module, context, definition)
        {:ok, sup}
    end
  end

  #------------
  #
  #------------
  def start_children(module, sup, context, definition \\ :auto) do
    if module.verbose() do
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

    _o = module.start_worker_supervisors(sup, context, definition)

    # @TODO - move into runtime meta.
    max_seconds = module._max_seconds()
    max_restarts = module._max_restarts()

    s = case Supervisor.start_child(sup, module.worker(module.pool_server(), [:deprecated, definition, context], [restart: :permanent, max_restarts: max_restarts, max_seconds: max_seconds])) do
      {:ok, pid} ->
        {:ok, pid}
      {:error, {:already_started, process2_id}} ->
        Supervisor.restart_child(module, process2_id)
      error ->
        Logger.error(fn ->
          {
            """

            #{module}.start_children(1) #{inspect module.pool_worker_supervisor()} Already Started. Handling unexepected state.
            #{inspect error}
            """, Noizu.ElixirCore.CallingContext.metadata(context)}
        end)
        :error
    end
    if s != :error && module.auto_load() do
      spawn fn -> module.pool_sever().load(context, module.options()) end
    end
    s
  end # end start_children



  def start_worker_supervisors(module, sup, definition, context) do
    supervisors = module.pool_server().available_supervisors()
    max_seconds = module._max_seconds()
    max_restarts = module._max_restarts()

    for s <- supervisors do
      case Supervisor.start_child(sup, module.supervisor(s, [definition, context], [restart: :permanent, max_restarts: max_restarts, max_seconds: max_seconds] )) do
        {:ok, _pool_supervisor} ->  :ok
        {:error, {:already_started, process_id}} ->
          case Supervisor.restart_child(sup, process_id) do
            {:ok, _pid} -> :ok
            error ->
              Logger.info(fn ->{
                                 """

                                 #{module}.start_children(3) #{inspect s} Already Started. Handling unexepected state.
                                 #{inspect error}
                                 """, Noizu.ElixirCore.CallingContext.metadata(context)}
              end)
              :error
          end
        error ->
          Logger.info(fn -> {
                              """

                              #{module}.start_children(4) #{inspect s} Already Started. Handling unexepected state.
                              #{inspect error}
                              """, Noizu.ElixirCore.CallingContext.metadata(context)}
          end)
          :error
      end # end case
    end # end for
  end # end start_worker_supervisors



  def imp_init(module, [context] = arg) do
    if module.verbose() || true do
      Logger.warn(fn -> {module.banner("#{module} INIT", "args: #{inspect arg}"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
    end
    strategy = module._strategy()
    max_seconds = module._max_seconds()
    max_restarts = module._max_restarts()
    module.supervise([], [{:strategy, strategy}, {:max_restarts, max_restarts}, {:max_seconds, max_seconds}, {:restart, :permanent}])
  end



  #---------
  #
  #---------
  defdelegate handle_call_catchall(module, uncaught, from, state), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  defdelegate handle_cast_catchall(module, uncaught, state), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  defdelegate handle_info_catchall(module, uncaught, state), to: Noizu.SimplePool.V2.Pool.DefaultImplementation


end