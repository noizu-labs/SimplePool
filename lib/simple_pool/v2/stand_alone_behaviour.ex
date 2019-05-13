#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.StandAloneBehaviour do
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

      #--------------------------
      # Overridable
      #--------------------------
      defoverridable [
        start: 2,
        stand_alone: 0
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
