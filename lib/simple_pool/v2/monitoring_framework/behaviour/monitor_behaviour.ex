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
    Primary node/module in charge of monitoring system.
  """
  @callback primary() :: any


  @callback start_services(context :: any, options :: any) :: any


  @doc """
    Check if node hosts a specific service/pool.
  """
  @callback supports_service?(elixir_server :: any, service :: any, CallingContext.t | nil, options :: Map.t) :: :ack | :nack | any

  @doc """
    Redistribute workers from input set across output set.
  """
  @callback rebalance(input :: elixir_server_group, output :: elixir_server_group, services :: service_group, CallingContext.t | nil, options :: Map.t) :: job_response

  @doc """
    Lock input servers and push existing load to other available servers.
  """
  @callback offload(input :: elixir_server_group, services :: service_group, CallingContext.t | nil, options :: Map.t) :: job_response

  @doc """
    Lock a node(s) from accepting new service workers of specified type(s).
  """
  @callback lock_services(elixir_servers :: any, services :: service_group, CallingContext.t | :all | nil, options :: Map.t) :: job_response

  @doc """
    Allow node(s) to resume accepting new workers of specified type(s).
  """
  @callback release_services(elixir_servers :: any, services :: service_group, CallingContext.t | :all | nil, options :: Map.t) :: job_response

  @doc """
    Select the node that should be used for a new worker.
  """
  @callback select_host(ref :: any, service :: atom, CallingContext.t | nil, options :: Map.t) :: {:ack, atom} | {:nack, details :: any} | {:error, details :: any}

  @doc """
    Record a server (elixir node) level event.
  """
  @callback record_server_event!(server :: atom, event :: atom, details :: any, CallingContext.t | nil, options :: Map.t) :: :ack | :nack | {:error, details :: any}

  @doc """
    Record a service (Pool) level event.
  """
  @callback record_service_event!(server :: atom, service :: module, event :: atom, details :: any, CallingContext.t | nil, options :: Map.t) :: :ack | :nack | {:error, details :: any}
end