#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.RouterBehaviour do

  @callback options() :: any
  @callback option(any, any) :: any

  @callback extended_call(any, any, any, any, any, any) :: any

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

  #@callback route_call(any, any, any) :: any
  #@callback route_cast(any, any) :: any
  #@callback route_info(any, any) :: any

  @callback s_call!(any, any, any, any) :: any
  @callback rs_call!(any, any, any, any) :: any

  @callback s_call(any, any, any, any) :: any
  @callback rs_call(any, any, any, any) :: any

  @callback s_cast!(any, any, any, any) :: any
  @callback rs_cast!(any, any, any, any) :: any

  @callback s_cast(any, any, any, any) :: any
  @callback rs_cast(any, any, any, any) :: any


  @callback link_forward!(any, any, any, any) :: any

  @callback run_on_host(any, any, any, any, any) :: any
  @callback cast_to_host(any, any, any, any, any) :: any

  @callback route_call(any, any, any) :: any
  @callback route_cast(any, any) :: any
  @callback route_info(any, any) :: any



  defmodule DefaultProvider do
    @moduledoc """
      DefaultRouter: Provides set of configurations most users are anticipated to desire.
       - Supports Redirects
       - Supports Safe Calls
    """


    defmacro __using__(options) do
      options = options || %{}
      options = %{}
      quote do
        alias Noizu.SimplePool.V2.Router.RouterProvider
        @options unquote(Macro.escape(options))
        @pool_server Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat()
        @default_timeout 30_000
        @behaviour Noizu.SimplePool.V2.RouterBehaviour

        def options(), do: @options
        def option(option, default \\ :not_found), do: Map.get(@options, option, default)

        def run_on_host(ref, mfa, context, options \\ nil, timeout \\ @default_timeout) do
          RouterProvider.run_on_host(@pool_server, ref, mfa, context, options, timeout)
        end

        def cast_to_host(ref, mfa, context, options \\ nil) do
          RouterProvider.cast_to_host(@pool_server, ref, mfa, context, options)
        end

        def self_call(call, context \\ nil, options \\ nil) do
          RouterProvider.self_call(@pool_server, call, context, options)
        end

        def self_cast(call, context \\ nil, options \\ nil) do
          RouterProvider.self_cast(@pool_server, call, context, options)
        end


        def internal_system_call(call, context \\ nil, options \\ nil) do
          RouterProvider.internal_system_call(@pool_server, call, context, options)
        end

        def internal_system_cast(call, context \\ nil, options \\ nil) do
          RouterProvider.internal_system_cast(@pool_server, call, context, options)
        end


        def remote_system_call(remote_node, call, context \\ nil, options \\ nil) do
          RouterProvider.remote_system_call(@pool_server, remote_node, call, context, options)
        end

        def remote_system_cast(remote_node, call, context \\ nil, options \\ nil) do
          RouterProvider.remote_system_cast(@pool_server, remote_node, call, context, options)
        end


        def internal_call(call, context \\ nil, options \\ nil) do
          RouterProvider.internal_call(@pool_server, call, context, options)
        end

        def internal_cast(call, context \\ nil, options \\ nil) do
          RouterProvider.internal_cast(@pool_server, call, context, options)
        end


        def remote_call(remote_node, call, context \\ nil, options \\ nil) do
          RouterProvider.remote_call(@pool_server, remote_node, call, context, options)
        end

        def remote_cast(remote_node, call, context \\ nil, options \\ nil) do
          RouterProvider.remote_cast(@pool_server, remote_node, call, context, options)
        end



        def s_call_unsafe(ref, extended_call, context, options, timeout) do
          RouterProvider.s_call_unsafe(@pool_server, ref, extended_call, context, options, timeout)
        end

        def s_cast_unsafe(ref, extended_call, context, options) do
          RouterProvider.s_cast_unsafe(@pool_server, ref, extended_call, context, options)
        end


        def s_call!(identifier, call, context, options \\ nil, timeout \\ nil) do
          RouterProvider.s_call_crash_protection!(@pool_server, identifier, call, context, options, timeout)
        end

        def rs_call!(identifier, call, context, options \\ nil, timeout \\ nil) do
          RouterProvider.rs_call_crash_protection!(@pool_server, identifier, call, context, options, timeout)
        end

        def s_call(identifier, call, context, options \\ nil, timeout \\ nil) do
          RouterProvider.s_call_crash_protection(@pool_server, identifier, call, context, options, timeout)
        end

        def rs_call(identifier, call, context, options \\ nil, timeout \\ nil) do
          RouterProvider.rs_call_crash_protection(@pool_server, identifier, call, context, options, timeout)
        end

        def s_cast!(identifier, call, context, options \\ nil) do
          RouterProvider.s_cast_crash_protection!(@pool_server, identifier, call, context, options)
        end

        def rs_cast!(identifier, call, context, options \\ nil) do
          RouterProvider.rs_cast_crash_protection!(@pool_server, identifier, call, context, options)
        end

        def s_cast(identifier, call, context, options \\ nil) do
          RouterProvider.s_cast_crash_protection(@pool_server, identifier, call, context, options)
        end

        def rs_cast(identifier, call, context, options \\ nil) do
          RouterProvider.rs_cast_crash_protection(@pool_server, identifier, call, context, options)
        end

        def link_forward!(link, call, context, options \\ nil) do
          RouterProvider.link_forward!(@pool_server, link, call, context, options)
        end

        def extended_call(s_type, ref, call, context, options, timeout) do
          RouterProvider.extended_call_with_redirect_support(@pool_server, s_type, ref, call, context, options, timeout)
        end

        def get_direct_link!(ref, context, options) do
          RouterProvider.get_direct_link!(@pool_server, ref, context, options)
        end


        #def route_call(envelope, from, state) do
        #  RouterProvider.route_call(@pool_server, envelope, from, state)
        #end

        #def route_cast(envelope, state) do
        #  RouterProvider.route_cast(@pool_server, envelope, state)
        #end

        #def route_info(envelope, state) do
        #  RouterProvider.route_info(@pool_server, envelope, state)
        #end





        defoverridable [
          options: 0,
          option: 2,

          extended_call: 6,

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

          #route_call: 3,
          #route_cast: 2,
          #route_info: 2,

          s_call!: 5,
          rs_call!: 5,

          s_call: 5,
          rs_call: 5,

          s_cast!: 4,
          rs_cast!: 4,

          s_cast: 4,
          rs_cast: 4,

          link_forward!: 4,

          run_on_host: 5,
          cast_to_host: 4,
        ]
      end
    end
  end

  defmodule PerformanceProvider do
    @moduledoc """
      PerformanceProvider: Router with redirect and exception handling disabled.
    """
    defmacro __using__(options) do
      options = options || %{}

      quote do
        alias Noizu.SimplePool.V2.Router.RouterProvider
        @options unquote(options)
        @pool_server Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat()

        @default_timeout 30_000
        @behaviour Noizu.SimplePool.V2.RouterBehaviour

        def options(), do: @options
        def option(option, default \\ :not_found), do: Map.get(@options, option, default)

        def run_on_host(ref, mfa, context, options \\ nil, timeout \\ @default_timeout) do
          RouterProvider.run_on_host(@pool_server, ref, mfa, context, options, timeout)
        end

        def cast_to_host(ref, mfa, context, options \\ nil) do
          RouterProvider.cast_to_host(@pool_server, ref, mfa, context, options)
        end

        def self_call(call, context \\ nil, options \\ nil) do
          RouterProvider.self_call(@pool_server, call, context, options)
        end

        def self_cast(call, context \\ nil, options \\ nil) do
          RouterProvider.self_cast(@pool_server, call, context, options)
        end


        def internal_system_call(call, context \\ nil, options \\ nil) do
          RouterProvider.internal_system_call(@pool_server, call, context, options)
        end

        def internal_system_cast(call, context \\ nil, options \\ nil) do
          RouterProvider.internal_system_cast(@pool_server, call, context, options)
        end


        def remote_system_call(remote_node, call, context \\ nil, options \\ nil) do
          RouterProvider.remote_system_call(@pool_server, remote_node, call, context, options)
        end

        def remote_system_cast(remote_node, call, context \\ nil, options \\ nil) do
          RouterProvider.remote_system_cast(@pool_server, remote_node, call, context, options)
        end


        def internal_call(call, context \\ nil, options \\ nil) do
          RouterProvider.internal_call(@pool_server, call, context, options)
        end

        def internal_cast(call, context \\ nil, options \\ nil) do
          RouterProvider.internal_cast(@pool_server, call, context, options)
        end


        def remote_call(remote_node, call, context \\ nil, options \\ nil) do
          RouterProvider.remote_call(@pool_server, remote_node, call, context, options)
        end

        def remote_cast(remote_node, call, context \\ nil, options \\ nil) do
          RouterProvider.remote_cast(@pool_server, remote_node, call, context, options)
        end



        def s_call_unsafe(ref, extended_call, context, options, timeout) do
          RouterProvider.s_call_unsafe(@pool_server, ref, extended_call, context, options, timeout)
        end

        def s_cast_unsafe(ref, extended_call, context, options) do
          RouterProvider.s_cast_unsafe(@pool_server, ref, extended_call, context, options)
        end


        def s_call!(identifier, call, context, options \\ nil, timeout \\ nil) do
          RouterProvider.s_call_no_crash_protection!(@pool_server, identifier, call, context, options, timeout)
        end

        def rs_call!(identifier, call, context, options \\ nil, timeout \\ nil) do
          RouterProvider.rs_call_no_crash_protection!(@pool_server, identifier, call, context, options, timeout)
        end

        def s_call(identifier, call, context, options \\ nil, timeout \\ nil) do
          RouterProvider.s_call_no_crash_protection(@pool_server, identifier, call, context, options, timeout)
        end

        def rs_call(identifier, call, context, options \\ nil, timeout \\ nil) do
          RouterProvider.rs_call_no_crash_protection(@pool_server, identifier, call, context, options, timeout)
        end

        def s_cast!(identifier, call, context, options \\ nil) do
          RouterProvider.s_cast_no_crash_protection!(@pool_server, identifier, call, context, options)
        end

        def rs_cast!(identifier, call, context, options \\ nil) do
          RouterProvider.rs_cast_no_crash_protection!(@pool_server, identifier, call, context, options)
        end

        def s_cast(identifier, call, context, options \\ nil) do
          RouterProvider.s_cast_no_crash_protection(@pool_server, identifier, call, context, options)
        end

        def rs_cast(identifier, call, context, options \\ nil) do
          RouterProvider.rs_cast_no_crash_protection(@pool_server, identifier, call, context, options)
        end

        def link_forward!(link, call, context, options \\ nil) do
          RouterProvider.link_forward!(@pool_server, link, call, context, options)
        end

        def extended_call(s_type, ref, call, context, options, timeout) do
          RouterProvider.extended_call_without_redirect_support(@pool_server, s_type, ref, call, context, options, timeout)
        end

        def get_direct_link!(ref, context, options) do
          RouterProvider.get_direct_link!(@pool_server, ref, context, options)
        end


        #def route_call(envelope, from, state) do
        #  RouterProvider.route_call(@pool_server, envelope, from, state)
        #end

        #def route_cast(envelope, state) do
        #  RouterProvider.route_cast(@pool_server, envelope, state)
        #end

        #def route_info(envelope, state) do
        #  RouterProvider.route_info(@pool_server, envelope, state)
        #end

        defoverridable [
          options: 0,
          options: 2,

          extended_call: 6,

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

          #route_call: 3,
          #route_cast: 2,
          #route_info: 2,

          s_call!: 5,
          rs_call!: 5,

          s_call: 5,
          rs_call: 5,

          s_cast!: 4,
          rs_cast!: 4,

          s_cast: 4,
          rs_cast: 4,

          link_forward!: 4,

          run_on_host: 5,
          cast_to_host: 5,
        ]
      end
    end
  end

end