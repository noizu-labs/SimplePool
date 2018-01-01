#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.MonitoringFramework.MonitorBehaviour.Default do
  require Logger
  @behaviour Noizu.SimplePool.MonitoringFramework.MonitorBehaviour

  def supports_service?(_server, _component, _context, _options \\ %{}) do
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

  def select_host(_ref, _component, _context, _options \\ %{}) do
    {:ack, node()}
  end


  def record_server_event!(server, event, details, context, options \\ %{}), do: :ack
  def record_service_event!(server, service, event, details, context, options \\ %{}), do: :ack

end