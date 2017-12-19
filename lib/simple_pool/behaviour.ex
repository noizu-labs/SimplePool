#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Behaviour do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList

  require Logger

  @callback option_settings() :: Map.t

  @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])
  @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])

  @modules ([:worker, :server, :worker_supervisor, :pool_supervisor])
  @default_modules ([:worker_supervisor, :pool_supervisor])
  @methods ([])

  @default_worker_options ([])
  @default_server_options ([])
  @default_worker_supervisor_options ([])
  @default_pool_supervisor_options ([])

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        default_modules: %OptionList{option: :default_modules, default: Application.get_env(:noizu_simple_pool, :default_modules, @default_modules), valid_members: @modules, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: Application.get_env(:noizu_simple_pool, :verbose, false)},
        worker_lookup_handler: %OptionValue{option: :worker_lookup_handler, default: Application.get_env(:noizu_simple_pool, :worker_lookup_handler, Noizu.SimplePool.WorkerLookupBehaviour)},
        worker_options: %OptionValue{option: :worker_options, default: Application.get_env(:noizu_simple_pool, :default_worker_options, @default_worker_options)},
        server_options: %OptionValue{option: :server_options, default: Application.get_env(:noizu_simple_pool, :default_server_options, @default_server_options)},
        worker_supervisor_options: %OptionValue{option: :worker_supervisor_options, default: Application.get_env(:noizu_simple_pool, :default_worker_supervisor_options, @default_worker_supervisor_options)},
        pool_supervisor_options: %OptionValue{option: :pool_supervisor_options, default: Application.get_env(:noizu_simple_pool, :default_pool_supervisor_options, @default_pool_supervisor_options)},
        worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
        server_provider: %OptionValue{option: :server_provider, default: Application.get_env(:noizu_simple_pool, :default_server_provider, Noizu.SimplePool.Server.ProviderBehaviour.Default)}
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

  def expand_worker_state_entity(base_module, worker_state_entity) do
    if worker_state_entity == :auto do
      Module.concat(base_module, "WorkerStateEntity")
    else
      worker_state_entity
    end
  end

  defmacro __using__(options) do
    option_settings = prepare_options(options)
    options = option_settings.effective_options
    #required = options.required
    #features = options.features
    default_modules = options.default_modules
    quote do
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.Behaviour
      @mod_name ("#{__MODULE__}")
      @worker_state_entity (expand_worker_state_entity(__MODULE__, unquote(options.worker_state_entity)))

      def banner(msg) do
        banner(@mod_name, msg)
      end

      def option_settings do
        unquote(Macro.escape(option_settings))
      end

      if (unquote(default_modules.worker)) do
        defmodule Worker do
          use Noizu.SimplePool.WorkerBehaviour, unquote(options.worker_options)
        end
      end

      if (unquote(default_modules.server)) do
        defmodule Server do
          use Noizu.SimplePool.ServerBehaviour, unquote(options.server_options)
          def lazy_load(state), do: state
        end
      end

      if (unquote(default_modules.worker_supervisor)) do
        defmodule WorkerSupervisor do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
      end

      if (unquote(default_modules.pool_supervisor)) do
        defmodule PoolSupervisor do
          use Noizu.SimplePool.PoolSupervisorBehaviour, unquote(options.pool_supervisor_options)
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
