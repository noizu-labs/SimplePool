#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.ClusterManagement.Cluster.Definition do
  @vsn 1.0
  @type t :: %__MODULE__{
               cluster: any,
               monitors: Map.t,
               telemetrics: Map.t,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    cluster: nil,
    monitors: %{},
    telemetrics: %{},
    meta: %{},
    vsn: @vsn
  ]

  def new(cluster) do
    %__MODULE__{
      cluster: cluster,
    }
  end
end