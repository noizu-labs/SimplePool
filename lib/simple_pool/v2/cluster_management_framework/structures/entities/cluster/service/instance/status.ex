#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Status do
  @vsn 1.0
  @type t :: %__MODULE__{
               service: any,
               node: any,
               service_monitor: any,
               service_process: any,
               service_error: any,
               status: atom,
               state: atom,
               pending_state: atom,
               health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.t,
               updated_on: DateTime.t,
               state_changed_on: DateTime.t,
               pending_state_changed_on: DateTime.t,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    service: nil,
    node: nil,
    service_monitor: nil,
    service_process: nil,
    service_error: nil,
    status: :unknown,
    state: :offline,
    pending_state: :offline,
    health_report: nil,
    updated_on: nil,
    state_changed_on: nil,
    pending_state_changed_on: nil,
    meta: %{},
    vsn: @vsn
  ]

  def new(service, node, pool_supervisor_pid, error) do
    %__MODULE__{
      service: service,
      node: node,
      service_monitor: pool_supervisor_pid && Process.monitor(pool_supervisor_pid),
      service_process: pool_supervisor_pid,
      service_error: error,
      updated_on: DateTime.utc_now(),
      state_changed_on: DateTime.utc_now(),
      pending_state_changed_on: DateTime.utc_now(),
    }
  end

end