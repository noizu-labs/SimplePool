#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.ServerMonitorBehaviour.DefaultImplementation do
  require Logger
  @behaviour Noizu.SimplePool.ServerMonitorBehaviour

  def supported_node(_server, _component, _context, _options \\ %{}) do
    :ack
  end

  def rebalance(_input, _output, _components, _context, _options \\ %{}) do
    {:ack, self()}
  end

  def lock(_servers, _components, _context, _options \\ %{}) do
    {:ack, self()}
  end

  def release(_servers, _components, _context, _options \\ %{}) do
    {:ack, self()}
  end

  def join(_servers, _settings, _context, _options \\ %{}) do
    {:ack, self()}
  end

  def select_host(_ref, _component, _context, _options \\ %{}) do
    {:ack, node()}
  end
end