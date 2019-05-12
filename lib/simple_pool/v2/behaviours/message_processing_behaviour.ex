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
          Logger.warn fn -> "Redirecting Call #{inspect call_server}-#{inspect call, pretty: true}\n\n" end
          try do
            Logger.error fn -> {"Redirect Failed! #{inspect call_server}-#{inspect fc, pretty: true}", Noizu.ElixirCore.CallingContext.metadata(context)} end
            # Clear lookup entry to allow system to assign correct entry and spawn new entry.
            call_server.worker_management().unregister!(ref, context, %{})
          rescue e -> Logger.error "[MessageProcessing] - Exception Raised #{inspect e}"
          catch e -> Logger.error "[MessageProcessing] - Exception Thrown #{inspect e}"
          end
          {:reply, {:s_retry, call_server, __MODULE__}, state}
        end

        def handle_call({:msg_envelope, {__MODULE__, _delivery_details}, call = {_s, _call, _context}}, from, state), do: handle_call(call, from, state)
        def handle_call({:msg_envelope, {call_server, {_call_type, ref, _timeout}}, call = {_type, _payload, context}}, _from, state) do
          Logger.warn fn -> "Redirecting Call #{inspect call_server}-#{inspect call, pretty: true}\n\n" end
          try do
            Logger.warn fn -> {"Redirecting Call #{inspect call_server}-#{inspect call, pretty: true}\n\n", Noizu.ElixirCore.CallingContext.metadata(context)} end
            # Clear lookup entry to allow system to assign correct entry and spawn new entry.
            call_server.worker_management().unregister!(ref, context, %{})
          rescue e -> Logger.error "[MessageProcessing] - Exception Raised #{inspect e}"
          catch e -> Logger.error "[MessageProcessing] - Exception Thrown #{inspect e}"
          end
          {:reply, {:s_retry, call_server, __MODULE__}, state}
        end

        @doc """
        Catchall
        """
        def handle_call(envelope, from, state), do: __call_handler(envelope, from, state)

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
        Catchall
        """
        def handle_cast(envelope, state), do: __cast_handler(envelope, state)

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
        Catchall
        """
        def handle_info(envelope, state), do: __info_handler(envelope, state)

        #===============================================================================================================
        # Default delegation
        #===============================================================================================================
        def default_call_router(envelope, from, state), do: nil
        def call_router(envelope, from, state), do: nil
        def __call_handler(envelope, from, state) do
          call_router(envelope, from, state) || default_call_router(envelope, from, state) || Noizu.SimplePool.V2.MessageProcessing.DefaultProvider.__delegate_call_handler(__MODULE__, envelope, from, state)
        end


        def default_cast_router(envelope, state), do: nil
        def cast_router(envelope, state), do: nil
        def __cast_handler(envelope, state) do
          cast_router(envelope, state) || default_cast_router(envelope, state) || Noizu.SimplePool.V2.MessageProcessing.DefaultProvider.__delegate_cast_handler(__MODULE__, envelope, state)
        end

        def default_info_router(envelope, state), do: nil
        def info_router(envelope, state), do: nil
        def __info_handler(envelope, state) do
          info_router(envelope, state) || default_info_router(envelope, state) || Noizu.SimplePool.V2.MessageProcessing.DefaultProvider.__delegate_info_handler(__MODULE__, envelope, state)
        end

        #===============================================================================================================
        # Overridable
        #===============================================================================================================
        defoverridable [
          call_router: 3,
          default_call_router: 3,
          __call_handler: 3,

          cast_router: 2,
          default_cast_router: 2,
          __cast_handler: 2,

          info_router: 2,
          default_info_router: 2,
          __info_handler: 2,
        ]
      end
    end
  end
end