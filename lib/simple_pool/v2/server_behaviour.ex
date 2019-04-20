#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.ServerBehaviour do
  @moduledoc """
  The ServerBehaviour provides the entry point for interacting with worker processes.
  It manages worker process creation and routing calls to the correct process/node/worker supervisor.

  For example the ChatRoomPool.Server would have methods such as  send_message(room_ref, msg, context) which would in turn
  forward a call into the supervisor responsible for room_ref.

  @todo break out core functionality (like routing) into sub modules which in turn are populated with use calls to their respective providers.
  This will allow us to design modules with completely different implementations and function signatures and provide a nice function access hierarchy.
  """

  require Logger

  @callback fetch(any, any, any, any) :: any
  @callback save!(any, any, any) :: any
  @callback save_async!(any, any, any) :: any
  @callback reload!(any, any, any) :: any
  @callback reload_async!(any, any, any) :: any
  @callback ping!(any, any, any) :: any
  @callback kill!(any, any, any) :: any
  @callback crash!(any, any, any) :: any
  @callback health_check!(any, any) :: any
  @callback health_check!(any, any, any) :: any
  @callback health_check!(any, any, any, any) :: any

  #=================================================================
  #=================================================================
  # @__using__
  #=================================================================
  #=================================================================
  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.Server.DefaultImplementation)
    option_settings = implementation.prepare_options(options)

    # Temporary Hardcoding
    router_provider = Noizu.SimplePool.V2.RouterBehaviour
    worker_management_provider = Noizu.SimplePool.V2.WorkerManagementBehaviour
    server_management_provider = Noizu.SimplePool.V2.ServerManagementBehaviour
    message_processing_provider = Noizu.SimplePool.V2.MessageProcessingBehaviour
    quote do
      # todo option value
      @timeout 30_000

      @behaviour Noizu.SimplePool.V2.ServerBehaviour
      alias Noizu.SimplePool.Worker.Link
      use GenServer
      require Logger

      #----------------------------------------------------------
      use Noizu.SimplePool.V2.PoolSettingsBehaviour.Inherited, unquote(option_settings)
      #----------------------------------------------------------

      #----------------------------------------------------------
      use unquote(message_processing_provider), unquote(option_settings)
      #----------------------------------------------------------


      #----------------------------------------------------------
      defmodule Router do
        use unquote(router_provider), unquote(option_settings)
      end
      #----------------------------------------------------------

      #----------------------------------------------------------
      defmodule WorkerManagement do
        use unquote(worker_management_provider), unquote(option_settings)
      end
      #----------------------------------------------------------

      #----------------------------------------------------------
      defmodule ServerManagement do
        use unquote(server_management_provider), unquote(option_settings)
      end
      #----------------------------------------------------------


      #---------------------------------------------------------
      # Built in Worker Convenience Methods.
      #---------------------------------------------------------
      @doc """
      Request information about a worker.
      """
      def fetch(ref, request \\ :state, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call!(ref, {:fetch, request}, context, options)
      end

      @doc """
      Tell a worker to save its state.
      """
      def save!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call!(identifier, :save!, context, options)
      end

      @doc """
      Tell a worker to save its state, do not wait for response.
      """
      def save_async!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast!(identifier, :save!, context, options)
      end

      @doc """
      Tell a worker to reload its state.
      """
      def reload!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call!(identifier, {:reload!, options}, context, options)
      end

      @doc """
      Tell a worker to reload its state, do not wait for a response.
      """
      def reload_async!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast!(identifier, {:reload!, options}, context, options)
      end

      @doc """
      Ping worker.
      """
      def ping!(identifier, context \\ nil, options \\ %{}) do
        timeout = options[:timeout] || @timeout
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_call(identifier, :ping!, context, options, timeout)
      end

      @doc """
      Send worker a kill request.
      """
      def kill!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast!(identifier, :kill!, context, options)
      end

      @doc """
      Send a worker a crash (throw error) request.
      """
      def crash!(identifier, context \\ nil, options \\ %{}) do
        context = context || Noizu.ElixirCore.CallingContext.system()
        __MODULE__.Router.s_cast!(identifier, :crash!, context, options)
      end

      @doc """
      Request a health report from worker.
      """
      def health_check!(identifier, %Noizu.ElixirCore.CallingContext{} = context) do
        __MODULE__.Router.s_call!(identifier, {:health_check!, %{}}, context)
      end
      def health_check!(identifier, health_check_options, %Noizu.ElixirCore.CallingContext{} = context) do
        __MODULE__.Router.s_call!(identifier, {:health_check!, health_check_options}, context)
      end
      def health_check!(identifier, health_check_options, %Noizu.ElixirCore.CallingContext{} = context, options) do
        __MODULE__.Router.s_call!(identifier, {:health_check!, health_check_options}, context, options)
      end

      defoverridable [
        fetch: 4,
        save!: 3,
        save_async!: 3,
        reload!: 3,
        reload_async!: 3,
        ping!: 3,
        kill!: 3,
        crash!: 3,
        health_check!: 2,
        health_check!: 3,
        health_check!: 4,
      ]

    end # end quote
  end #end __using__
end
