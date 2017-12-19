#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.ServerMonitorBehaviour do
  @type job_handle :: pid | function | mfa | {:ref, module, any}
  @type job_status :: {:error, details :: any} | {:completed, integer} | {:started, integer} | {:queued, integer}
  @type job_response :: {:ok, job_handle} | {:error, details :: any}
  @type server_group :: list | :all | MapSet.t | Map.t
  @type component_group :: list | :all | MapSet.t | Map.t

  @callback supported_node(server :: any, component :: any, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: :ack | :nack | any

  @callback rebalance(input :: server_group, output :: server_group, components :: component_group, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: job_response
  @callback lock(input :: server_group, components :: component_group, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: job_response
  @callback release(input :: server_group, components :: component_group, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: job_response

  @callback join(server :: atom, settings :: Map.t, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: job_response

  @callback select_node(ref :: any, server :: atom, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: {:ack, atom} | {:nack, details :: any} | {:error, details :: any}
end