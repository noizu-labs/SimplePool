#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.PoolBehaviour do
  @moduledoc """
    The Noizu.SimplePool.V2.Behaviour provides the entry point for Worker Pools.
    The developer will define a pool such as ChatRoomPool that uses the Noizu.SimplePool.V2.Behaviour Implementation
    before going on to define worker and server implementations.

    The module is relatively straight forward, it provides methods to get pool information (pool worker, pool supervisor)
    compile options, runtime settings (via the FastGlobal library and our meta function).
  """

  @callback stand_alone() :: any


  defmodule Default do
    @moduledoc """
      Default Implementation for the top level Pool module.
    """
    alias Noizu.ElixirCore.OptionSettings
    alias Noizu.ElixirCore.OptionValue
    alias Noizu.ElixirCore.OptionList
    require Logger

    @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])
    @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])

    @modules ([:worker, :server, :worker_supervisor, :pool_supervisor, :monitor])
    @default_modules ([])

    @default_worker_options ([])
    @default_server_options ([])
    @default_worker_supervisor_options ([])
    @default_pool_supervisor_options ([])
    @default_monitor_options ([])

    #---------
    #
    #---------
    def prepare_options(options) do
      settings = %OptionSettings{
        option_settings: %{
          features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
          default_modules: %OptionList{option: :default_modules, default: Application.get_env(:noizu_simple_pool, :default_modules, @default_modules), valid_members: @modules, membership_set: true},
          verbose: %OptionValue{option: :verbose, default: Application.get_env(:noizu_simple_pool, :verbose, false)},
          monitor_options: %OptionValue{option: :monitor_options, default: Application.get_env(:noizu_simple_pool, :default_monitor_options, @default_monitor_options)},
          worker_options: %OptionValue{option: :worker_options, default: Application.get_env(:noizu_simple_pool, :default_worker_options, @default_worker_options)},
          server_options: %OptionValue{option: :server_options, default: Application.get_env(:noizu_simple_pool, :default_server_options, @default_server_options)},
          worker_supervisor_options: %OptionValue{option: :worker_supervisor_options, default: Application.get_env(:noizu_simple_pool, :default_worker_supervisor_options, @default_worker_supervisor_options)},
          pool_supervisor_options: %OptionValue{option: :pool_supervisor_options, default: Application.get_env(:noizu_simple_pool, :default_pool_supervisor_options, @default_pool_supervisor_options)},
          worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
          max_supervisors: %OptionValue{option: :max_supervisors, default: Application.get_env(:noizu_simple_pool, :default_max_supervisors, 100)},
        }
      }

      # Copy verbose, features, and worker_state_entity into nested module option lists.
      initial = OptionSettings.expand(settings, options)
      modifications = Map.take(initial.effective_options, [:worker_options, :server_options, :worker_supervisor_options, :pool_supervisor_options])
                      |> Enum.reduce(%{},
                           fn({k,v},acc) ->
                             v = v
                                 |> Keyword.put_new(:verbose, initial.effective_options.verbose)
                                 |> Keyword.put_new(:features, initial.effective_options.features)
                                 |> Keyword.put_new(:worker_state_entity, initial.effective_options.worker_state_entity)
                             Map.put(acc, k, v)
                           end)
      %OptionSettings{initial| effective_options: Map.merge(initial.effective_options, modifications)}
    end
  end

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.PoolBehaviour.Default)
    option_settings = implementation.prepare_options(Macro.expand(options, __CALLER__))
    options = option_settings.effective_options
    default_modules = options.default_modules
    max_supervisors = options.max_supervisors
    message_processing_provider = Noizu.SimplePool.V2.MessageProcessingBehaviour.DefaultProvider

    quote do
      require Logger
      #@todo define some methods to make behaviour.
      @behaviour Noizu.SimplePool.V2.PoolBehaviour

      @implementation unquote(implementation)
      @module __MODULE__
      @max_supervisors unquote(max_supervisors)

      use Noizu.SimplePool.V2.SettingsBehaviour.Base, unquote([option_settings: option_settings])
      use unquote(message_processing_provider), unquote(option_settings)

      #--------------------------
      # Methods
      #--------------------------

      def start(context \\ nil, definition \\ :auto), do: __MODULE__.PoolSupervisor.start_link(context, definition)
      def stand_alone(), do: false

      #--------------------------
      # Overridable
      #--------------------------
      defoverridable [
        start: 2,
        stand_alone: 0
      ]

      #--------------------------
      # Sub Modules
      #--------------------------
      if (unquote(default_modules.worker)) do
        defmodule Worker do
          use Noizu.SimplePool.V2.WorkerBehaviour, unquote(options.worker_options)
        end
      end

      if (unquote(default_modules.server)) do
        defmodule Server do
          use Noizu.SimplePool.V2.ServerBehaviour, unquote(options.server_options)
          def lazy_load(state), do: state
        end
      end

      if (unquote(default_modules.worker_supervisor)) do
        defmodule WorkerSupervisor do
          use Noizu.SimplePool.V2.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
        end
      end

      if (unquote(default_modules.pool_supervisor)) do
        defmodule PoolSupervisor do
          use Noizu.SimplePool.V2.PoolSupervisorBehaviour, unquote(options.pool_supervisor_options)
        end
      end

      if (unquote(default_modules.monitor)) do
        defmodule Monitor do
          use Noizu.SimplePool.V2.MonitorBehaviour, unquote(options.monitor_options)
        end
      end

    end # end quote
  end #end __using__
end
