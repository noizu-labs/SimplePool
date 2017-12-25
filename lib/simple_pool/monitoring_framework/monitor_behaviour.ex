#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.MonitoringFramework.MonitorBehaviour do
  @type job_handle :: pid | function | mfa | {:ref, module, any}
  @type job_status :: {:error, details :: any} | {:completed, integer} | {:started, integer} | {:queued, integer}
  @type job_response :: {:ok, job_handle} | {:error, details :: any}
  @type server_group :: list | :all | MapSet.t | Map.t
  @type component_group :: list | :all | MapSet.t | Map.t

  @callback supports_service?(server :: any, component :: any, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: :ack | :nack | any

  @callback rebalance(input :: server_group, output :: server_group, components :: component_group, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: job_response

  @callback lock(input :: server_group, components :: component_group, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: job_response
  @callback release(input :: server_group, components :: component_group, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: job_response

  #@callback join(server :: atom, settings :: Map.t, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: job_response
  #@callback leave(server :: atom, settings :: Map.t, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: job_response

  @callback select_host(ref :: any, server :: atom, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: {:ack, atom} | {:nack, details :: any} | {:error, details :: any}

  @callback record_server_event(server :: atom, event :: atom, details :: any, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: :ack | :nack | {:error, details :: any}
  @callback record_service_event(server :: atom, service :: module, event :: atom, details :: any, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: :ack | :nack | {:error, details :: any}


end