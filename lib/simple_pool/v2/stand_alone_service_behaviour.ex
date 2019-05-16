#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.StandAloneServiceBehaviour do
  @moduledoc """
    The Noizu.SimplePool.V2.Behaviour provides the entry point for Worker Pools.
    The developer will define a pool such as ChatRoomPool that uses the Noizu.SimplePool.V2.Behaviour Implementation
    before going on to define worker and server implementations.

    The module is relatively straight forward, it provides methods to get pool information (pool worker, pool supervisor)
    compile options, runtime settings (via the FastGlobal library and our meta function).
  """

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.PoolBehaviour.Default)
    option_settings = implementation.prepare_options(Macro.expand(options, __CALLER__))

    # Set stand alone flag.
    option_settings = option_settings
                      |> put_in([Access.key(:effective_options), :stand_alone], true)
                      |> put_in([Access.key(:effective_options), :monitor_options, :stand_alone], true)
                      |> put_in([Access.key(:effective_options), :worker_options, :stand_alone], true)
                      |> put_in([Access.key(:effective_options), :server_options, :stand_alone], true)
                      |> put_in([Access.key(:effective_options), :worker_supervisor_options, :stand_alone], true)
                      |> put_in([Access.key(:effective_options), :pool_supervisor_options, :stand_alone], true)

    options = option_settings.effective_options

    default_modules = options.default_modules
    message_processing_provider = Noizu.SimplePool.V2.MessageProcessingBehaviour.DefaultProvider

    quote do
      require Logger
      @behaviour Noizu.SimplePool.V2.PoolBehaviour
      @implementation unquote(implementation)
      @module __MODULE__

      use Noizu.SimplePool.V2.SettingsBehaviour.Base, unquote([option_settings: option_settings, stand_alone: true])
      use unquote(message_processing_provider), unquote(option_settings)

      #--------------------------
      # Methods
      #--------------------------
      def start(context \\ nil, definition \\ :auto), do: __MODULE__.PoolSupervisor.start_link(context, definition)
      def stand_alone(), do: true


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



      #--------------------------
      # Overridable
      #--------------------------
      defoverridable [
        start: 2,
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

      #-----------------------------------------
      # Sub Modules
      #-----------------------------------------

      # Note, no WorkerSupervisor as this is a stand alone service with no children.

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

      # Note user must implement Server sub module.

    end # end quote
  end #end __using__
end
