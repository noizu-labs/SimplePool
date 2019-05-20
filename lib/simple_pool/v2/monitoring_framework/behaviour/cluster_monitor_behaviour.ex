#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.MonitoringFramework.ClusterMonitorBehaviour do
  alias Noizu.ElixirCore.CallingContext


  @doc """
    Redistribute workers from input set, across output set.
  """
  @callback rebalance(from_nodes :: any, to_nodes :: any, services :: any, CallingContext.t | nil, Map.t) :: any


  @doc """
    Lock service(s) on specified server(s) and redistribute load to remaining nodes.
  """
  @callback offload(from_nodes :: any, services :: any, CallingContext.t | nil, Map.t) :: any

  @doc """
    Lock a node(s) from accepting new service workers of specified type(s).
  """
  @callback lock_services(lock_servers :: any, lock_services :: any, CallingContext.t | nil, options :: Map.t) :: any


  @doc """
    Allow node(s) to resume accepting new workers of specified type(s).
  """
  @callback release_services(lock_servers :: any, lock_services :: any, CallingContext.t | nil, options :: Map.t) :: any

  @doc """
    Select the node that should be used for a new worker.
  """
  @callback select_host(ref :: any, service :: atom, CallingContext.t | nil, options :: Map.t) :: {:ack, atom} | {:nack, details :: any} | {:error, details :: any}

  @doc """
    Record a server (elixir node) level event.
  """
  @callback record_cluster_event!(event :: atom, details :: any, CallingContext.t | nil, options :: Map.t) :: :ack | :nack | {:error, details :: any}

  @doc """
  retrieve cluster wide health check
  """
  @callback health_check(CallingContext.t | nil, Map.t) :: any
end