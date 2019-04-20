#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.RouterBehaviour do
  require Logger
  @callback extended_call(any, any, any, any) :: any

  @callback self_call(any, any, any) :: any
  @callback self_cast(any, any, any) :: any

  @callback internal_system_call(any, any, any) :: any
  @callback internal_system_cast(any, any, any) :: any

  @callback internal_call(any, any, any) :: any
  @callback internal_cast(any, any, any) :: any

  @callback remote_system_call(any, any, any, any) :: any
  @callback remote_system_cast(any, any, any, any) :: any

  @callback remote_call(any, any, any, any) :: any
  @callback remote_cast(any, any, any, any) :: any

  @callback get_direct_link!(any, any, any) :: any

  @callback s_call_unsafe(any, any, any, any, any) :: any
  @callback s_cast_unsafe(any, any, any, any) :: any

  @callback route_call(any, any, any) :: any
  @callback route_cast(any, any) :: any
  @callback route_info(any, any) :: any

  @callback s_call!(any, any, any, any) :: any
  @callback s_call(any, any, any, any) :: any

  @callback s_cast!(any, any, any, any) :: any
  @callback s_cast(any, any, any, any) :: any

  @callback link_forward!(any, any, any, any) :: any

  @callback run_on_host(any, any, any, any, any) :: any
  @callback cast_to_host(any, any, any, any, any) :: any

  defmacro __using__(_options) do
    quote do

      def extended_call(_ref, _timeout, _call, _context), do: throw :pri0_extended_call

      def self_call(_call, _context \\ nil, _options \\ %{}), do: throw :pri0_self_call
      def self_cast(_call, _context \\ nil, _options \\ %{}), do: throw :pri0_self_cast

      def internal_system_call(_call, _context \\ nil, _options \\ %{}), do: throw :pri0_internal_system_call
      def internal_system_cast(_call, _context \\ nil, _options \\ %{}), do: throw :pri0_internal_system_cast

      def internal_call(_call, _context \\ nil, _options \\ %{}), do: throw :pri0_internal_call
      def internal_cast(_call, _context \\ nil, _options \\ %{}), do: throw :pri0_internal_cast

      def remote_system_call(_remote_node, _call, _context \\ nil, _options \\ %{}), do: throw :pri0_remote_system_call
      def remote_system_cast(_remote_node, _call, _context \\ nil, _options \\ %{}), do: throw :pri0_remote_system_cast

      def remote_call(_remote_node, _call, _context \\ nil, _options \\ %{}), do: throw :pri0_remote_call
      def remote_cast(_remote_node, _call, _context \\ nil, _options \\ %{}), do: throw :pri0_remote_cast

      def get_direct_link!(_ref, _context, _options), do: throw :pri0_get_direct_link!

      def s_call_unsafe(_ref, _extended_call, _context, _options, _timeout), do: throw :pri0_s_call_unsafe
      def s_cast_unsafe(_ref, _extended_call, _context, _options), do: throw :pri0_s_cast_unsafe

      def route_call(_envelope, _from, _state), do: throw :pri0_route_call
      def route_cast(_envelope, _state), do: throw :pri0_route_cast
      def route_info(_envelope, _state), do: throw :pri0_route_info

      def s_call!(_identifier, _call, _context, _options \\ %{}, _timeout \\ nil), do: throw :pri0_s_call!
      def s_call(_identifier, _call, _context, _options \\ %{}, _timeout \\ nil), do: throw :pri0_s_call


      def s_cast!(_identifier, _call, _context, _options \\ %{}), do: throw :pri0_s_cast!
      def s_cast(_identifier, _call, _context, _options \\ %{}), do: throw :pri0_s_cast

      def link_forward!(_link, _call, _context, _options \\ %{}), do: throw :pri0_link_forward!

      def as_cast({:reply, _reply, state}), do: {:noreply, state}
      def as_cast({:noreply, state}), do: {:noreply, state}
      def as_cast({:stop, reason, _reply, state}), do: {:stop, reason, state}
      def as_cast({:stop, reason, state}), do: {:stop, reason, state}

      def run_on_host(_ref, _mfa, _context, _options \\ %{}, _timeout \\ 30_000), do: throw :pri0_run_on_host
      def cast_to_host(_ref, _mfa, _context, _options \\ %{}, _timeout \\ 30_000), do: throw :pri0_cast_to_host


      defoverridable [
        extended_call: 4,

        self_call: 3,
        self_cast: 3,

        internal_system_call: 3,
        internal_system_cast: 3,

        internal_call: 3,
        internal_cast: 3,

        remote_system_call: 4,
        remote_system_cast: 4,

        remote_call: 4,
        remote_cast: 4,

        get_direct_link!: 3,
        s_call_unsafe: 5,
        s_cast_unsafe: 4,
        route_call: 3,
        route_cast: 2,
        route_info: 2,

        s_call!: 5,
        s_call: 5,
        s_cast!: 4,
        s_cast: 4,
        link_forward!: 4,

        run_on_host: 5,
        cast_to_host: 5,
      ]
    end
  end
end