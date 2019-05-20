#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.MonitoringFramework.MonitorBehaviour do
  @type job_handle :: pid | function | mfa | {:ref, module, any}
  @type job_status :: {:error, details :: any} | {:completed, integer} | {:started, integer} | {:queued, integer}
  @type job_response :: {:ok, job_handle} | {:error, details :: any}
  @type elixir_server_group :: list | :all | MapSet.t | Map.t
  @type service_group :: list | :all | MapSet.t | Map.t

  alias Noizu.ElixirCore.CallingContext

  @doc """
    Start services controlled by monitor.
  """
  @callback bring_services_online(context :: any, options :: any) :: any

  @doc """
    Wait on server state.
  """
  @callback status_wait(any, context :: any, options :: any) :: any


  @doc """
    Check if node hosts a specific service/pool.
  """
  @callback supports_service?(service :: any, CallingContext.t | nil, options :: Map.t) :: :ack | :nack | any

  @doc """
    Lock a node(s) from accepting new service workers of specified type(s).
  """
  @callback lock_services(services :: service_group, CallingContext.t | :all | nil, options :: Map.t) :: job_response

  @doc """
    Allow node(s) to resume accepting new workers of specified type(s).
  """
  @callback release_services(services :: service_group, CallingContext.t | :all | nil, options :: Map.t) :: job_response


  @doc """
    Set server wide lock on all new workers.
  """
  @callback lock_server(CallingContext.t | :all | nil, options :: Map.t) :: job_response

  @doc """
    Remove server wide lock.
  """
  @callback release_server(CallingContext.t | :all | nil, options :: Map.t) :: job_response


  @doc """
    Select the node that should be used for a new worker. @todo deprecated, enduser should call cluster monitor as this call spans nodes.
  """
  @callback select_host(ref :: any, service :: atom, CallingContext.t | nil, options :: Map.t) :: {:ack, atom} | {:nack, details :: any} | {:error, details :: any}

  @doc """
    Record a server (elixir node) level event.
  """
  @callback record_server_event!(event :: atom, details :: any, CallingContext.t | nil, options :: Map.t) :: :ack | :nack | {:error, details :: any}

  @doc """
    Record a server (elixir node) level event.
  """
  @callback record_service_event!(service :: atom, event :: atom, details :: any, CallingContext.t | nil, options :: Map.t) :: :ack | :nack | {:error, details :: any}


  @doc """
   Obtain server health check.
  """
  @callback health_check(any, any) :: any
end