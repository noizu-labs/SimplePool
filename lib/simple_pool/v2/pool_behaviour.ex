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

    @features ([:auto_load, :auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])
    @default_features ([:auto_load, :lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])

    @modules ([:worker, :server, :worker_supervisor, :pool_supervisor, :monitor])
    @default_modules ([])

    @default_worker_options ([])
    @default_server_options ([])
    @default_worker_supervisor_options ([])
    @default_pool_supervisor_options ([])
    @default_monitor_options ([])
    @default_registry_options ([partitions: 256, keys: :unique])

    #---------
    #
    #---------
    def prepare_options(options) do
      settings = %OptionSettings{
        option_settings: %{
          features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
          default_modules: %OptionList{option: :default_modules, default: Application.get_env(:noizu_simple_pool, :default_modules, @default_modules), valid_members: @modules, membership_set: true},
          verbose: %OptionValue{option: :verbose, default: Application.get_env(:noizu_simple_pool, :verbose, false)},

          dispatch_table: %OptionValue{option: :dispatch_table, default: :auto},
          #dispatch_monitor_table: %OptionValue{option: :dispatch_monitor_table, default: :auto},
          registry_options: %OptionValue{option: :registry_options, default: Application.get_env(:noizu_simple_pool, :default_registry_options, @default_registry_options)},

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
      defdelegate start(definition \\ :default, context \\ nil), to: __MODULE__.PoolSupervisor, as: :start_link
      def start_remote(elixir_node, definition \\ :default, context \\ nil) do
        if (elixir_node == node()) do
          __MODULE__.PoolSupervisor.start_link(definition, context)
        else
          :rpc.call(elixir_node, __MODULE__.PoolSupervisor, :start_link, [definition, context])
        end
      end

      def stand_alone(), do: false

      #-------------- Routing Delegates -------------------
      # Convenience methods should be placed at the pool level,
      # which will in turn hook into the Server.Router and worker spawning logic
      # to delivery commands to the correct worker processes.
      #----------------------------------------------------
      defdelegate s_call(identifier, call, context, options \\ nil, timeout \\ nil), to: __MODULE__.Server.Router
      defdelegate s_call!(identifier, call, context, options \\ nil, timeout \\ nil), to: __MODULE__.Server.Router
      defdelegate s_cast(identifier, call, context, options \\ nil), to: __MODULE__.Server.Router
      defdelegate s_cast!(identifier, call, context, options \\ nil), to: __MODULE__.Server.Router
      defdelegate get_direct_link!(ref, context, options), to: __MODULE__.Server.Router
      defdelegate link_forward!(link, call, context, options \\ nil), to: __MODULE__.Server.Router
      defdelegate server_call(call, context \\ nil, options \\ nil), to: __MODULE__.Server.Router, as: :self_call
      defdelegate server_cast(call, context \\ nil, options \\ nil), to: __MODULE__.Server.Router, as: :self_cast
      defdelegate server_internal_call(call, context \\ nil, options \\ nil), to: __MODULE__.Server.Router, as: :internal_call
      defdelegate server_internal_cast(call, context \\ nil, options \\ nil), to: __MODULE__.Server.Router, as: :internal_cast
      defdelegate remote_server_internal_call(remote_node, call, context \\ nil, options \\ nil), to: __MODULE__.Server.Router, as: :remote_call
      defdelegate remote_server_internal_cast(remote_node, call, context \\ nil, options \\ nil), to: __MODULE__.Server.Router, as: :remote_cast
      defdelegate server_system_call(call, context \\ nil, options \\ nil), to: __MODULE__.Server.Router, as: :internal_system_call
      defdelegate server_system_cast(call, context \\ nil, options \\ nil), to: __MODULE__.Server.Router, as: :internal_system_cast
      defdelegate remote_server_system_call(elixir_node, call, context \\ nil, options \\ nil), to: __MODULE__.Server.Router, as: :remote_system_call
      defdelegate remote_server_system_cast(elixir_node, call, context \\ nil, options \\ nil), to: __MODULE__.Server.Router, as: :remote_system_cast

      #==========================================================
      # Built in Worker Convenience Methods.
      #==========================================================
      defdelegate fetch!(ref, request \\ :state, context \\ nil, options \\ %{}), to: __MODULE__.Server
      defdelegate save!(ref, args \\ {}, context \\ nil, options \\ %{}), to: __MODULE__.Server
      defdelegate save_async!(ref, args \\ {}, context \\ nil, options \\ %{}), to: __MODULE__.Server
      defdelegate reload!(ref, args \\ {}, context \\ nil, options \\ %{}), to: __MODULE__.Server
      defdelegate reload_async!(ref, args \\ {}, context \\ nil, options \\ %{}), to: __MODULE__.Server
      defdelegate load!(ref, args \\ {}, context \\ nil, options \\ %{}), to: __MODULE__.Server
      defdelegate load_async!(ref, args \\ {}, context \\ nil, options \\ %{}), to: __MODULE__.Server
      defdelegate ping(ref, args \\ {}, context \\ nil, options \\ %{}), to: __MODULE__.Server
      defdelegate kill!(ref, args \\ {}, context \\ nil, options \\ %{}), to: __MODULE__.Server
      defdelegate crash!(ref, args \\ {}, context \\ nil, options \\ %{}), to: __MODULE__.Server
      defdelegate health_check!(ref, args \\ {}, context \\ nil, options \\ %{}), to: __MODULE__.Server


      #--------------------------
      # Overridable
      #--------------------------
      defoverridable [
        start: 2,
        start_remote: 3,
        stand_alone: 0,

        #-----------------------------
        # Routing Overrides
        #-----------------------------
        s_call: 5,
        s_call!: 5,
        s_cast: 4,
        s_cast!: 4,
        get_direct_link!: 3,
        link_forward!: 4,
        server_call: 3,
        server_cast: 3,
        server_internal_call: 3,
        server_internal_cast: 3,
        remote_server_internal_call: 4,
        remote_server_internal_cast: 4,
        server_system_call: 3,
        server_system_cast: 3,
        remote_server_system_call: 4,
        remote_server_system_cast: 4,

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
