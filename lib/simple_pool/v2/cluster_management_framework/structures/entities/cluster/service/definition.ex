#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Definition do
  @vsn 1.0
  @type t :: %__MODULE__{
               service: any,
               worker_window: Map.t,
               node_window: Map.t,
               monitors: Map.t,
               telemetrics: Map.t,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    service: nil,
    worker_window: %{low: nil, high: nil, target: nil},
    node_window: %{low: nil, high: nil, target: nil},
    monitors: %{},
    telemetrics: %{},
    meta: %{},
    vsn: @vsn
  ]

  def new(service, worker_window, node_window) do
    %__MODULE__{
      service: service,
      worker_window: worker_window,
      node_window: node_window,
    }
  end
end