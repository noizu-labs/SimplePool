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

  def join(_servers, _settings, _context, _options \\ %{}) do
    {:ack, self()}
  end

  def leave(_servers, _settings, _context, _options \\ %{}) do
    {:ack, self()}
  end

  def select_host(_ref, _component, _context, _options \\ %{}) do
    {:ack, node()}
  end

  def report_service_health(server, service, health, context, options \\ %{}) do
    :ack
  end

  def report_server_health(server, health, context, options \\ %{}) do
    :ack
  end


  def record_server_event(server, event, details, context, options \\ %{}), do: :ack
  def record_service_event(server, service, event, details, context, options \\ %{}), do: :ack

  def refresh_hints(service, context, options \\ %{}), do: :ack


end