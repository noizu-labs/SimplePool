#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Pool.DefaultImplementation do
  @moduledoc """
    Default Implementation for the top level Pool module.
  """
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList
  require Logger

  @callback option_settings() :: Map.t

  @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])
  @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])

  @modules ([:worker, :server, :worker_supervisor, :pool_supervisor])
  @default_modules ([:worker_supervisor, :pool_supervisor])
  @methods ([:banner, :options, :option_settings])

  @default_worker_options ([])
  @default_server_options ([])
  @default_worker_supervisor_options ([])
  @default_pool_supervisor_options ([])

  #---------
  #
  #---------
  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        implementation: %OptionValue{option: :max_restarts, default: Application.get_env(:noizu_simple_pool, :default_pool_provider, Noizu.SimplePool.V2.Pool.DefaultImplementation)},
        features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        default_modules: %OptionList{option: :default_modules, default: Application.get_env(:noizu_simple_pool, :default_modules, @default_modules), valid_members: @modules, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: Application.get_env(:noizu_simple_pool, :verbose, false)},
        worker_lookup_handler: %OptionValue{option: :worker_lookup_handler, default: Application.get_env(:noizu_simple_pool, :worker_lookup_handler, Noizu.SimplePool.V2.WorkerLookupBehaviour)},
        worker_options: %OptionValue{option: :worker_options, default: Application.get_env(:noizu_simple_pool, :default_worker_options, @default_worker_options)},
        server_options: %OptionValue{option: :server_options, default: Application.get_env(:noizu_simple_pool, :default_server_options, @default_server_options)},
        worker_supervisor_options: %OptionValue{option: :worker_supervisor_options, default: Application.get_env(:noizu_simple_pool, :default_worker_supervisor_options, @default_worker_supervisor_options)},
        pool_supervisor_options: %OptionValue{option: :pool_supervisor_options, default: Application.get_env(:noizu_simple_pool, :default_pool_supervisor_options, @default_pool_supervisor_options)},
        worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
        server_provider: %OptionValue{option: :server_provider, default: Application.get_env(:noizu_simple_pool, :default_server_provider, Noizu.SimplePool.V2.Server.ProviderBehaviour.Default)},
        max_supervisors: %OptionValue{option: :max_supervisors, default: Application.get_env(:noizu_simple_pool, :default_max_supervisors, 100)},
      }
    }

    initial = OptionSettings.expand(settings, options)
    modifications = Map.take(initial.effective_options, [:worker_options, :server_options, :worker_supervisor_options, :pool_supervisor_options])
                    |> Enum.reduce(%{},
                         fn({k,v},acc) ->
                           v = v
                               |> Keyword.put_new(:verbose, initial.effective_options.verbose)
                               |> Keyword.put_new(:features, initial.effective_options.features)
                               |> Keyword.put_new(:worker_state_entity, initial.effective_options.worker_state_entity)
                               |> Keyword.put_new(:server_provider, initial.effective_options.server_provider)
                           Map.put(acc, k, v)
                         end)
                    |> Map.put(:required, List.foldl(@methods, %{}, fn(x, acc) -> Map.put(acc, x, initial.effective_options.only[x] && !initial.effective_options.override[x]) end))

    %OptionSettings{initial| effective_options: Map.merge(initial.effective_options, modifications)}
  end

  @doc """
  Return a banner string.
  ------------- Example -----------
  Multi-Line
  Banner
  ---------------------------------
  """
  def banner(header, msg) do
    header_len = String.length(header)
    len = 120

    sub_len = div(header_len, 2)
    rem = rem(header_len, 2)

    l_len = 59 - sub_len
    r_len = 59 - sub_len - rem

    char = "*"

    lines = String.split(msg, "\n", trim: true)

    top = "\n#{String.duplicate(char, l_len)} #{header} #{String.duplicate(char, r_len)}"
    bottom = String.duplicate(char, len) <> "\n"
    middle = for line <- lines do
      "#{char} " <> line
    end
    Enum.join([top] ++ middle ++ [bottom], "\n")
  end

  #---------
  # Is this needed?
  #---------
  def pool_worker_state_entity(pool, :auto), do: Module.concat(pool, "WorkerStateEntity")
  def pool_worker_state_entity(_pool, worker_state_entity), do: worker_state_entity

  @doc """
  Return Meta Information for specified module.
  """
  def meta(module) do
    case FastGlobal.get(module.meta_key(), :no_entry) do
      :no_entry ->
        update = module.meta_init()
        module.meta(update)
        update
      v = %{} -> v
    end
  end

  @doc """
  Update Meta Information for module.
  """
  def meta(module, update) do
    if Semaphore.acquire({{:meta, :write}, module}, 1) do
      existing = case FastGlobal.get(module.meta_key(), :no_entry) do
        :no_entry -> module.meta_init()
        v -> v
      end
      update = Map.merge(existing, update)
      FastGlobal.put(module.meta_key(), update)
      update
    else
      false
    end
  end

  @doc """
  Initial Meta Information for Module.
  """
  def meta_init(module) do
    verbose = case module.options().verbose do
      :auto -> Application.get_env(:noizu_simple_pool, :verbose, false)
      v -> v
    end
    %{
      verbose: verbose,
    }
  end

  @doc """
  Get pool for module.
  """
  def pool(module), do: module


  @doc """
  Get Worker Supervisor for module.
  """
  def pool_worker_supervisor(pool), do: Module.concat([pool, "WorkerSupervisor"])


  @doc """
  Get Server for module.
  """
  def pool_server(pool), do: Module.concat([pool, "Server"])

  @doc """
  Get Worker for module.
  """
  def pool_worker(pool), do: Module.concat([pool, "Worker"])

  @doc """
  Get Pool Supervisor for module.
  """
  def pool_supervisor(pool), do: Module.concat([pool, "PoolSupervisor"])


  # The below should be in a helper method module.

  @doc """
  handle_call catchall
  """
  def handle_call_catchall(module, uncaught, _from, state) do
    Logger.warn(fn -> "Uncaught handle_call to #{module} . . . #{inspect uncaught}" end)
    {:noreply, state}
  end

  @doc """
  handle_cast catchall
  """
  def handle_cast_catchall(module, uncaught, state) do
    Logger.warn(fn -> "Uncaught handle_cast to #{module} . . . #{inspect uncaught}" end)
    {:noreply, state}
  end

  @doc """
  handle_info catchall
  """
  def handle_info_catchall(module, uncaught, state) do
    Logger.warn(fn -> "Uncaught handle_info to #{module} . . . #{inspect uncaught}" end)
    {:noreply, state}
  end

end