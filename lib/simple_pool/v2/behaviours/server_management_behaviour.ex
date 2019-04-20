#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.ServerManagementBehaviour do
  require Logger

  @callback start_link(any, any, any) :: any
  @callback init(any) :: any
  @callback terminate(any, any) :: any
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
      @server Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat()
      @router Module.concat(@server, Router)
      @wm Module.concat(@server, WorkerManagement)

      @doc """

      """
      def start_link(sup, definition, context), do: throw :pri0

      @doc """

      """
      def init(args), do: throw :pri0

      @doc """

      """
      def terminate(reason, state), do: throw :pri0

      @doc """

      """
      def default_definition(), do: throw :pri0

      @doc """

      """
      def enable_server!(elixir_node), do: throw :pri0

      @doc """

      """
      def disable_server!(elixir_node), do: throw :pri0

      @doc """

      """
      def status(context \\ nil), do: throw :pri0

      @doc """

      """
      def load(context \\ nil, settings \\ %{}), do: throw :pri0

      @doc """

      """
      def load_complete(this, process, context), do: throw :pri0

      @doc """

      """
      def status_wait(target_state, context, timeout \\ :infinity), do: throw :pri0

      @doc """

      """
      def entity_status(context, options \\ %{}), do: throw :pri0

      @doc """

      """
      def server_kill!(context \\ nil, options \\ %{}), do: throw :pri0

      @doc """

      """
      def service_health_check!(%Noizu.ElixirCore.CallingContext{} = context), do: throw :pri0
      def service_health_check!(health_check_options, %Noizu.ElixirCore.CallingContext{} = context), do: throw :pri0
      def service_health_check!(health_check_options, %Noizu.ElixirCore.CallingContext{} = context, options), do: throw :pri0


      @doc """

      """
      def record_service_event!(event, details, context, options), do: throw :pri0

      defoverridable [
        start_link: 3,
        init: 1,
        terminate: 2,

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