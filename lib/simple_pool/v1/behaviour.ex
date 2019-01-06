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
        server_provider: %OptionValue{option: :server_provider, default: Application.get_env(:noizu_simple_pool, :default_server_provider, Noizu.SimplePool.Server.ProviderBehaviour.Default)},
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
    max_supervisors = options.max_supervisors
    quote do
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.Behaviour
      @mod_name ("#{__MODULE__}")
      @worker_state_entity (expand_worker_state_entity(__MODULE__, unquote(options.worker_state_entity)))
      @max_supervisors unquote(max_supervisors)
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

        if @max_supervisors >= 1 do
          defmodule WorkerSupervisor_S1 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end

        if @max_supervisors >= 2 do
          defmodule WorkerSupervisor_S2 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 3 do
          defmodule WorkerSupervisor_S3 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 4 do
          defmodule WorkerSupervisor_S4 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 5 do
          defmodule WorkerSupervisor_S5 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 6 do
          defmodule WorkerSupervisor_S6 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 7 do
          defmodule WorkerSupervisor_S7 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 8 do
          defmodule WorkerSupervisor_S8 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 9 do
          defmodule WorkerSupervisor_S9 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 10 do
          defmodule WorkerSupervisor_S10 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 11 do
          defmodule WorkerSupervisor_S11 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 12 do
          defmodule WorkerSupervisor_S12 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 13 do
          defmodule WorkerSupervisor_S13 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 14 do
          defmodule WorkerSupervisor_S14 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 15 do
          defmodule WorkerSupervisor_S15 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 16 do
          defmodule WorkerSupervisor_S16 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 17 do
          defmodule WorkerSupervisor_S17 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 18 do
          defmodule WorkerSupervisor_S18 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 19 do
          defmodule WorkerSupervisor_S19 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 20 do
          defmodule WorkerSupervisor_S20 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 21 do
          defmodule WorkerSupervisor_S21 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 22 do
          defmodule WorkerSupervisor_S22 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 23 do
          defmodule WorkerSupervisor_S23 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 24 do
          defmodule WorkerSupervisor_S24 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 25 do
          defmodule WorkerSupervisor_S25 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 26 do
          defmodule WorkerSupervisor_S26 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 27 do
          defmodule WorkerSupervisor_S27 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 28 do
          defmodule WorkerSupervisor_S28 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 29 do
          defmodule WorkerSupervisor_S29 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 30 do
          defmodule WorkerSupervisor_S30 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 31 do
          defmodule WorkerSupervisor_S31 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 32 do
          defmodule WorkerSupervisor_S32 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 33 do
          defmodule WorkerSupervisor_S33 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 34 do
          defmodule WorkerSupervisor_S34 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 35 do
          defmodule WorkerSupervisor_S35 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 36 do
          defmodule WorkerSupervisor_S36 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 37 do
          defmodule WorkerSupervisor_S37 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 38 do
          defmodule WorkerSupervisor_S38 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 39 do
          defmodule WorkerSupervisor_S39 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 40 do
          defmodule WorkerSupervisor_S40 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end

        if @max_supervisors >= 41 do
          defmodule WorkerSupervisor_S41 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 42 do
          defmodule WorkerSupervisor_S42 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 43 do
          defmodule WorkerSupervisor_S43 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 44 do
          defmodule WorkerSupervisor_S44 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 45 do
          defmodule WorkerSupervisor_S45 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 46 do
          defmodule WorkerSupervisor_S46 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 47 do
          defmodule WorkerSupervisor_S47 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 48 do
          defmodule WorkerSupervisor_S48 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 49 do
          defmodule WorkerSupervisor_S49 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 50 do
          defmodule WorkerSupervisor_S50 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end

        if @max_supervisors >= 51 do
          defmodule WorkerSupervisor_S51 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 52 do
          defmodule WorkerSupervisor_S52 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 53 do
          defmodule WorkerSupervisor_S53 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 54 do
          defmodule WorkerSupervisor_S54 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 55 do
          defmodule WorkerSupervisor_S55 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 56 do
          defmodule WorkerSupervisor_S56 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 57 do
          defmodule WorkerSupervisor_S57 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 58 do
          defmodule WorkerSupervisor_S58 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 59 do
          defmodule WorkerSupervisor_S59 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 60 do
          defmodule WorkerSupervisor_S60 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end


        if @max_supervisors >= 61 do
          defmodule WorkerSupervisor_S61 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 62 do
          defmodule WorkerSupervisor_S62 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 63 do
          defmodule WorkerSupervisor_S63 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 64 do
          defmodule WorkerSupervisor_S64 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 65 do
          defmodule WorkerSupervisor_S65 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 66 do
          defmodule WorkerSupervisor_S66 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 67 do
          defmodule WorkerSupervisor_S67 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 68 do
          defmodule WorkerSupervisor_S68 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 69 do
          defmodule WorkerSupervisor_S69 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 70 do
          defmodule WorkerSupervisor_S70 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end

        if @max_supervisors >= 71 do
          defmodule WorkerSupervisor_S71 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 72 do
          defmodule WorkerSupervisor_S72 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 73 do
          defmodule WorkerSupervisor_S73 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 74 do
          defmodule WorkerSupervisor_S74 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 75 do
          defmodule WorkerSupervisor_S75 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 76 do
          defmodule WorkerSupervisor_S76 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 77 do
          defmodule WorkerSupervisor_S77 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 78 do
          defmodule WorkerSupervisor_S78 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 79 do
          defmodule WorkerSupervisor_S79 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 80 do
          defmodule WorkerSupervisor_S80 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end


        if @max_supervisors >= 81 do
          defmodule WorkerSupervisor_S81 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 82 do
          defmodule WorkerSupervisor_S82 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 83 do
          defmodule WorkerSupervisor_S83 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 84 do
          defmodule WorkerSupervisor_S84 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 85 do
          defmodule WorkerSupervisor_S85 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 86 do
          defmodule WorkerSupervisor_S86 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 87 do
          defmodule WorkerSupervisor_S87 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 88 do
          defmodule WorkerSupervisor_S88 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 89 do
          defmodule WorkerSupervisor_S89 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 90 do
          defmodule WorkerSupervisor_S90 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end


        if @max_supervisors >= 91 do
          defmodule WorkerSupervisor_S91 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 92 do
          defmodule WorkerSupervisor_S92 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 93 do
          defmodule WorkerSupervisor_S93 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 94 do
          defmodule WorkerSupervisor_S94 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 95 do
          defmodule WorkerSupervisor_S95 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 96 do
          defmodule WorkerSupervisor_S96 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 97 do
          defmodule WorkerSupervisor_S97 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 98 do
          defmodule WorkerSupervisor_S98 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 99 do
          defmodule WorkerSupervisor_S99 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
        if @max_supervisors >= 100 do
          defmodule WorkerSupervisor_S100 do
            use Noizu.SimplePool.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
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
