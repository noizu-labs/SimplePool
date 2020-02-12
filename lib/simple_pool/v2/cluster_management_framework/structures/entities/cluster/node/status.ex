#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Status do
  @vsn 1.0
  @type t :: %__MODULE__{
               node: any,
               status: atom,
               state: atom,
               desired_state: atom,
               health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.t,
               updated_on: DateTime.t,
               state_changed_on: DateTime.t,
               desired_state_changed_on: DateTime.t,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    node: nil,
    status: :unknown,
    state: :offline,
    desired_state: :offline,
    health_report: nil,
    updated_on: nil,
    state_changed_on: nil,
    desired_state_changed_on: nil,
    meta: %{},
    vsn: @vsn
  ]

  def new(node) do
    %__MODULE__{
      node: node,
    }
  end

end