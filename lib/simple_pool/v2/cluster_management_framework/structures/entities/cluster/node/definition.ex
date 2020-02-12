#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Definition do
  @vsn 1.0
  @type t :: %__MODULE__{
               node: any,
               worker_window: Map.t,
               ram_window: Map.t,
               cpu_window: Map.t,
               disk_window: Map.t,
               weight: float,
               monitors: Map.t,
               telemetrics: Map.t,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    node: nil,
    worker_window: %{low: nil, high: nil, target: nil},
    ram_window: %{low: nil, high: nil, target: nil},
    cpu_window: %{low: nil, high: nil, target: nil},
    disk_window: %{low: nil, high: nil, target: nil},
    weight: 1.0,
    monitors: %{},
    telemetrics: %{},
    meta: %{},
    vsn: @vsn
  ]

  def new(node, worker_window, ram_window, cpu_window, disk_window, weight) do
    %__MODULE__{
      node: node,
      worker_window: worker_window,
      ram_window: ram_window,
      cpu_window: cpu_window,
      disk_window: disk_window,
      weight: weight
    }
  end
end