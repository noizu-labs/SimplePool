#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.MessageProcessingBehaviour do
  require Logger

  @callback handle_call(any, any, any) :: any
  @callback handle_cast(any, any) :: any
  @callback handle_info(any, any) :: any
  @callback m_call_handler(any, any, any, any) :: any
  @callback m_cast_handler(any, any, any) :: any
  @callback m_info_handler(any, any, any) :: any
  @callback s_call_handler(any, any, any, any) :: any
  @callback s_cast_handler(any, any, any) :: any
  @callback s_info_handler(any, any, any) :: any
  @callback i_call_handler(any, any, any, any) :: any
  @callback i_cast_handler(any, any, any) :: any
  @callback i_info_handler(any, any, any) :: any


  defmacro __using__(_options) do
    quote do

      @doc """

      """
      def handle_call(envelope, from, state), do: throw :pri0

      @doc """

      """
      def handle_cast(envelope, state), do: throw :pri0

      @doc """

      """
      def handle_info(envelope, state), do: throw :pri0

      @doc """

      """
      def m_call_handler(call, context, from, state), do: throw :pri0

      @doc """

      """
      def m_cast_handler(call, context, state), do: throw :pri0

      @doc """

      """
      def m_info_handler(call, context, state), do: throw :pri0

      @doc """

      """
      def s_call_handler(call, context, from, state), do: throw :pri0

      @doc """

      """
      def s_cast_handler(call, context, state), do: throw :pri0

      @doc """

      """
      def s_info_handler(call, context, state), do: throw :pri0

      @doc """

      """
      def i_call_handler(call, context, from, state), do: throw :pri0

      @doc """

      """
      def i_cast_handler(call, context, state), do: throw :pri0

      @doc """

      """
      def i_info_handler(call, context, state), do: throw :pri0

      defoverridable [
        handle_call: 3,
        handle_cast: 2,
        handle_info: 2,
        m_call_handler: 4,
        m_cast_handler: 3,
        m_info_handler: 3,
        s_call_handler: 4,
        s_cast_handler: 3,
        s_info_handler: 3,
        i_call_handler: 4,
        i_cast_handler: 3,
        i_info_handler: 3,
      ]
    end
  end
end