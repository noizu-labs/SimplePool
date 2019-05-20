#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.MonitoringFramework.ServiceState do
  @vsn 1.0
  @type t :: %__MODULE__{
               pool: module,
               health: any,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    pool: nil,
    health: 0,
    meta: %{},
    vsn: @vsn
  ]
end
