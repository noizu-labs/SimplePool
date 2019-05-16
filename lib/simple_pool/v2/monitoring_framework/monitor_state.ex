#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.MonitoringFramework.MonitorState do
  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: module,
               configuration: Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration.t,
               services: Map.t,
               event_agent: pid | nil,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    identifier: nil,
    configuration: nil,
    services: %{},
    event_agent: nil,
    meta: %{},
    vsn: @vsn
  ]
end
