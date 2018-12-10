#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerSupervisor.DefaultImplementation do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList

  require Logger


  @methods ([:start_link, :child, :init, :verbose, :options, :option_settings])

  @default_max_seconds (5)
  @default_max_restarts (1000)
  @default_strategy (:one_for_one)

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: :auto},
        restart_type: %OptionValue{option: :restart_type, default: Application.get_env(:noizu_simple_pool, :pool_restart_type, :transient)},
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

  #-----------
  #
  #-----------
  def start_link(module, definition, context) do
    if module.verbose() do
      Logger.info(fn -> {module.banner("#{module}.start_link"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
      :skip
    end
    Supervisor.start_link(module, [definition, context], [{:name, module}])
  end

  #-----------
  #
  #-----------
  def child(module, ref, context) do
    module.worker(module.pool_worker(), [ref, context], [id: ref, restart: module._restart_type()])
  end

  def child(module, ref, params, context) do
    module.worker(module.pool_worker(), [ref, params, context], [id: ref, restart: module._restart_type()])
  end

  def child(module, ref, params, context, options) do
    restart = options[:restart] || module._restart_type()
    module.worker(module.pool_worker(), [ref, params, context], [id: ref, restart: restart])
  end

  #-----------
  #
  #-----------
  def init(module, [_definition, context]) do
    if module.verbose() do
      Logger.info(fn -> {module.banner("#{module} INIT", "args: #{inspect context}"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
    end
    module.supervise([], [{:strategy,  module._strategy()}, {:max_restarts, module._max_restarts()}, {:max_seconds, module._max_seconds()}])
  end


  #---------
  #
  #---------
  defdelegate handle_call_catchall(module, uncaught, from, state), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  defdelegate handle_cast_catchall(module, uncaught, state), to: Noizu.SimplePool.V2.Pool.DefaultImplementation
  defdelegate handle_info_catchall(module, uncaught, state), to: Noizu.SimplePool.V2.Pool.DefaultImplementation


end