#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.MessageProcessingBehaviour do
  require Logger

  @callback handle_call_catch_all(any, any, any) :: any
  @callback handle_cast_catch_all(any, any) :: any
  @callback handle_info_catch_all(any, any) :: any

  defmodule DefaultProvider do
    defmacro __using__(_options) do
      quote do
        require Logger
        @module __MODULE__

        #-----------------------------------------------------
        # handle_call
        #-----------------------------------------------------
        @doc """
        Message Redirect Support (V2) not compatible with V1
        """
        def handle_call({:msg_redirect, {__MODULE__, _delivery_details}, call = {_s, _call, _context}}, from, state), do: handle_call(call, from, state)
        def handle_call({:msg_redirect, {call_server, {_call_type, ref, _timeout}}, call = {_type, _payload, context}} = fc, _from, state) do
          try do
            Logger.error fn -> {"Redirect Failed! #{inspect call_server}-#{inspect fc, pretty: true}", Noizu.ElixirCore.CallingContext.metadata(context)} end
            # Clear lookup entry to allow system to assign correct entry and spawn new entry.
            call_server.worker_management().unregister!(ref, context, %{})
          rescue e -> Logger.error "[MessageProcessing] - Exception Raised #{inspect e}"
          catch e -> Logger.error "[MessageProcessing] - Exception Thrown #{inspect e}"
          end
          {:reply, :s_retry, state}
        end

        def handle_call({:msg_envelope, {__MODULE__, _delivery_details}, call = {_s, _call, _context}}, from, state), do: handle_call(call, from, state)
        def handle_call({:msg_envelope, {call_server, {_call_type, ref, _timeout}}, call = {_type, _payload, context}}, _from, state) do
          try do
            Logger.warn fn -> {"Redirecting Call #{inspect call_server}-#{inspect call, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
            # Clear lookup entry to allow system to assign correct entry and spawn new entry.
            call_server.worker_management().unregister!(ref, context, %{})
          rescue e -> Logger.error "[MessageProcessing] - Exception Raised #{inspect e}"
          catch e -> Logger.error "[MessageProcessing] - Exception Thrown #{inspect e}"
          end
          {:reply, :s_retry, state}
        end

        @doc """
        Standard or Message
        """
        def handle_call(_envelope = {:s, call, context}, from, state), do: s_call_handler(call, from, state, context)

        @doc """
        System Message
        """
        def handle_call(_envelope = {:m, call, context}, from, state), do: m_call_handler(call, from, state, context)

        @doc """
        Internal Message
        """
        def handle_call(_envelope = {:i, call, context}, from, state), do: i_call_handler(call, from, state, context)

        #-----------------------------------------------------
        # handle_cast
        #-----------------------------------------------------
        def handle_cast({:msg_redirect, {__MODULE__, _delivery_details}, call = {_s, _call, _context}}, state), do: handle_cast(call, state)
        def handle_cast({:msg_redirect, {call_server, {call_type, ref, _timeout}}, call = {_type, payload, context}} = fc, state) do
          spawn fn ->
            try do
              Logger.warn fn -> {"Redirect Failed #{inspect call_server}-#{inspect call, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
              # Clear lookup entry to allow system to assign correct entry and spawn new entry.
              call_server.worker_management().unregister!(ref, context, %{})
              apply(call_server.router(), call_type, [ref, payload, context]) # todo, deal with call options.
            rescue e -> Logger.error "[MessageProcessing] - Exception Raised #{inspect e}"
            catch e -> Logger.error "[MessageProcessing] - Exception Thrown #{inspect e}"
            end
          end
          {:noreply, state}
        end

        def handle_cast({:msg_envelope, {__MODULE__, _delivery_details}, call = {_s, _call, _context}}, state), do: handle_cast(call, state)
        def handle_cast({:msg_envelope, {call_server, {call_type, ref, _timeout}}, call = {_type, payload, context}}, state) do
          spawn fn ->
            try do
              Logger.warn fn -> {"Redirecting Cast #{inspect call_server}-#{inspect call, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
              # Clear lookup entry to allow system to assign correct entry and spawn new entry.
              call_server.worker_management().unregister!(ref, context, %{})
              apply(call_server.router(), call_type, [ref, payload, context]) # todo, deal with call options.
            rescue e -> Logger.error "[MessageProcessing] - Exception Raised #{inspect e}"
            catch e -> Logger.error "[MessageProcessing] - Exception Thrown #{inspect e}"
            end
          end
          {:noreply, state}
        end


        @doc """
        Standard or Message
        """
        def handle_cast(_envelope = {:s, call, context}, state), do: s_cast_handler(call, state, context)

        @doc """
        System Message
        """
        def handle_cast(_envelope = {:m, call, context}, state), do: m_cast_handler(call, state, context)

        @doc """
        Internal Message
        """
        def handle_cast(_envelope = {:i, call, context}, state), do: i_cast_handler(call, state, context)

        #-----------------------------------------------------
        # handle_info
        #-----------------------------------------------------
        def handle_info({:msg_redirect, {__MODULE__, _delivery_details}, call = {_s, _call, _context}}, state), do: handle_info(call, state)
        def handle_info({:msg_redirect, {call_server, {call_type, ref, _timeout}}, call = {_type, payload, context}} = fc, state) do
          spawn fn ->
            try do
              Logger.warn fn -> {"Redirect Failed #{inspect call_server}-#{inspect call, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
              # Clear lookup entry to allow system to assign correct entry and spawn new entry.
              call_server.worker_management().unregister!(ref, context, %{})
              apply(call_server.router(), call_type, [ref, payload, context]) # todo, deal with call options.
            rescue e -> Logger.error "[MessageProcessing] - Exception Raised #{inspect e}"
            catch e -> Logger.error "[MessageProcessing] - Exception Thrown #{inspect e}"
            end
          end
          {:noreply, state}
        end

        def handle_info({:msg_envelope, {__MODULE__, _delivery_details}, call = {_s, _call, _context}}, state), do: handle_info(call, state)
        def handle_info({:msg_envelope, {call_server, {call_type, ref, _timeout}}, call = {_type, payload, context}}, state) do
          spawn fn ->
            try do
              Logger.warn fn -> {"Redirecting Cast #{inspect call_server}-#{inspect call, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
              # Clear lookup entry to allow system to assign correct entry and spawn new entry.
              call_server.worker_management().unregister!(ref, context, %{})
              apply(call_server.router(), call_type, [ref, payload, context]) # todo, deal with call options.
            rescue e -> Logger.error "[MessageProcessing] - Exception Raised #{inspect e}"
            catch e -> Logger.error "[MessageProcessing] - Exception Thrown #{inspect e}"
            end
          end
          {:noreply, state}
        end

        @doc """
        Standard or Message
        """
        def handle_info(_envelope = {:s, call, context}, state), do: s_info_handler(call, state, context)

        @doc """
        System Message
        """
        def handle_info(_envelope = {:m, call, context}, state), do: m_info_handler(call, state, context)

        @doc """
        Internal Message
        """
        def handle_info(_envelope = {:i, call, context}, state), do: i_info_handler(call, state, context)


        #===============================================================================================================
        # Catch All methods for info, cast, and call
        #===============================================================================================================
        def handle_call_catch_all(envelope, _from, state) do
          # todo logging
          {:noreply, state}
        end

        def handle_cast_catch_all(envelope, state) do
          # todo logging
          {:noreply, state}
        end

        def handle_info_catch_all(envelope, state) do
          # todo logging
          {:noreply, state}
        end


        def s_call_handler(_call, _from, _state, _context), do: throw "s_call_handler not overridden by #{__MODULE__}"
        def m_call_handler(_call, _from, _state, _context), do: throw "m_call_handler not overridden by #{__MODULE__}"
        def i_call_handler(_call, _from, _state, _context), do: throw "i_call_handler not overridden by #{__MODULE__}"

        def s_cast_handler(_call, _state, _context), do: throw "s_cast_handler not overridden by #{__MODULE__}"
        def m_cast_handler(_call, _state, _context), do: throw "m_cast_handler not overridden by #{__MODULE__}"
        def i_cast_handler(_call, _state, _context), do: throw "i_cast_handler not overridden by #{__MODULE__}"

        def s_info_handler(_call, _state, _context), do: throw "s_info_handler not overridden by #{__MODULE__}"
        def m_info_handler(_call, _state, _context), do: throw "m_info_handler not overridden by #{__MODULE__}"
        def i_info_handler(_call, _state, _context), do: throw "i_info_handler not overridden by #{__MODULE__}"


        #===============================================================================================================
        # Overridable
        #===============================================================================================================
        defoverridable [
          handle_call_catch_all: 3,
          handle_cast_catch_all: 2,
          handle_info_catch_all: 2,

          s_call_handler: 4,
          m_call_handler: 4,
          i_call_handler: 4,

          s_cast_handler: 3,
          m_cast_handler: 3,
          i_cast_handler: 3,

          s_info_handler: 3,
          m_info_handler: 3,
          i_info_handler: 3,
        ]

      end
    end
  end
end