#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.ClusterManagement.HealthReport.Check do
  @vsn 1.0
  @type t :: %__MODULE__{
               name: any,
               provider: any,
               summary: any,
               details: Map.t,
               updated_on: DateTime.t,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    name: nil,
    provider: nil,
    summary: :pending,
    details: nil,
    updated_on: nil,
    meta: %{},
    vsn: @vsn
  ]
end