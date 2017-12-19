#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.ServerMonitorBehaviour.DefaultImplementation do
  require Logger
  @behaviour Noizu.SimplePool.ServerMonitorBehaviour

  def supported_node(server, component, context, options) do
    :ack
  end

  def rebalance(input, output, components, context, options) do
    {:ok, self()}
  end

  def lock(servers, components, context, options) do
    {:ok, self()}
  end

  def release(servers, components, context, options) do
    {:ok, self()}
  end

  def join(servers, settings, context, options) do
    {:ok, self()}
  end

  def select_node(ref, component, context, options) do
    node()
  end
end