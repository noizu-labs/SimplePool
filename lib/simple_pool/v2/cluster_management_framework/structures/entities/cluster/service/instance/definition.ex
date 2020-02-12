#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Definition do
  @vsn 1.0
  @type t :: %__MODULE__{
               service: any,
               node: any,
               launch_parameters: Map.t,
               worker_window: Map.t,
               weight: float,
               monitors: Map.t,
               telemetrics: Map.t,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    service: nil,
    node: nil,
    launch_parameters: :auto,
    worker_window: %{low: nil, high: nil, target: nil},
    weight: 1.0,
    monitors: %{},
    telemetrics: %{},
    meta: %{},
    vsn: @vsn
  ]

  def new(service, node, worker_window, weight) do
    %__MODULE__{
      service: service,
      node: node,
      worker_window: worker_window,
      weight: weight
    }
  end
end