#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
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
  @methods ([:banner, :options, :option_settings])

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
    required = options.required
    #features = options.features
    default_modules = options.default_modules
    quote do
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.Behaviour
      @mod_name ("#{__MODULE__}")
      @worker_state_entity (expand_worker_state_entity(__MODULE__, unquote(options.worker_state_entity)))

      @options unquote(Macro.escape(options))
      @option_settings unquote(Macro.escape(option_settings))

      if (unquote(required.banner)) do
        def banner(msg), do: banner(@mod_name, msg)
      end

      if (unquote(required.option_settings)) do
      def option_settings(), do: @option_settings
      end

      if (unquote(required.options)) do
        def options(), do: @options
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
        defmodule WorkerSupervisor_S1 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S2 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S3 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S4 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S5 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S6 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S7 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S8 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S9 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S10 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S11 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S12 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S13 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S14 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S15 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S16 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S17 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S18 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S19 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S20 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S21 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S22 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S23 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S24 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S25 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S26 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S27 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S28 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S29 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S30 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S31 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S32 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S33 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S34 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S35 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S36 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S37 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S38 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S39 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
        defmodule WorkerSupervisor_S40 do
          use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
      end

      if (unquote(default_modules.pool_supervisor)) do
        defmodule PoolSupervisor do
          use Noizu.SimplePool.PoolSupervisorBehaviour, unquote(options.pool_supervisor_options)
        end
      end

    end # end quote
  end #end __using__
end
