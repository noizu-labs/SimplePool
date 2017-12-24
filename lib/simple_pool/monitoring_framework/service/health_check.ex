#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.MonitoringFramework.Service.HealthCheck do
  alias Noizu.SimplePool.MonitoringFramework.Service.Definition

  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               time_stamp: DateTime.t,
               status: :online | :degraded | :critical | :offline,
               directive: :free | :locked | :maintenance,
               definition: Definition.t,
               allocated: Map.t,
               health_index: float,
               events: [LifeCycleEvent.t],
               vsn: any
             }

  defstruct [
    identifier: nil,
    time_stamp: nil,
    status: :offline,
    directive: :locked,
    definition: nil,
    allocated: nil,
    health_index: 0.0,
    events: [],
    vsn: @vsn
  ]
end