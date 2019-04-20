#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.ServiceManagementBehaviour do
  require Logger

  @callback default_definition() :: any
  @callback enable_server!(any) :: any
  @callback disable_server!(any) :: any
  @callback status(any) :: any
  @callback load(any, any) :: any
  @callback load_complete(any, any, any) :: any
  @callback status_wait(any, any, any) :: any
  @callback entity_status(any, any) :: any
  @callback server_kill!(any, any) :: any
  @callback service_health_check!(any) :: any
  @callback service_health_check!(any, any) :: any
  @callback service_health_check!(any, any, any) :: any
  @callback record_service_event!(any, any, any, any) :: any

  defmacro __using__(_options) do
    quote do
      require Logger
      @server Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat()
      @router Module.concat(@server, Router)
      @wm Module.concat(@server, WorkerManagement)

      @doc """

      """
      def default_definition() do
          @server.meta()[:default_definition]
          |> put_in([Access.key(:time_stamp)], DateTime.utc_now())
      end

      @doc """

      """
      def enable_server!(elixir_node), do: throw :pri0_enable_server!

      @doc """

      """
      def disable_server!(elixir_node), do: throw :pri0_disable_server!

      @doc """

      """
      def status(context \\ nil), do: throw :pri0_status

      @doc """

      """
      def load(context \\ nil, settings \\ %{}), do: throw :pri0_load

      @doc """

      """
      def load_complete(this, process, context), do: throw :pri0_load_complete

      @doc """

      """
      def status_wait(target_state, context, timeout \\ :infinity), do: throw :pri0_status_wait

      @doc """

      """
      def entity_status(context, options \\ %{}), do: throw :pri0_entity_status

      @doc """

      """
      def server_kill!(context \\ nil, options \\ %{}), do: throw :pri0_server_kill!

      @doc """

      """
      def service_health_check!(%Noizu.ElixirCore.CallingContext{} = context), do: throw :pri0_service_health_check!
      def service_health_check!(health_check_options, %Noizu.ElixirCore.CallingContext{} = context), do: throw :pri0_service_health_check!
      def service_health_check!(health_check_options, %Noizu.ElixirCore.CallingContext{} = context, options), do: throw :pri0_service_health_check!


      @doc """

      """
      def record_service_event!(event, details, context, options), do: Logger.error("Record Service Event V2 NYI")

      defoverridable [

        default_definition: 0,

        enable_server!: 1,
        disable_server!: 1,

        status: 1,

        load: 2,
        load_complete: 3,

        status_wait: 3,

        entity_status: 2,

        server_kill!: 2,

        service_health_check!: 1,
        service_health_check!: 2,
        service_health_check!: 3,

        record_service_event!: 4,

      ]
    end
  end
end