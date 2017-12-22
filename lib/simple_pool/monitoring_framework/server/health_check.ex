#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.MonitoringFramework.Server.HealthCheck do
  alias Noizu.SimplePool.MonitoringFramework.Server.Resources
  alias Noizu.SimplePool.MonitoringFramework.LifeCycleEvent

  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               master_node: boolean,
               time_stamp: DateTime.t,
               status: :online | :degraged | :critical | :offline | :halting,
               directive: :open | :locked | :maintenance,
               services: %{module => Noizu.SimplePool.MonitoringFramework.Services.HealthCheck.t},
               resources: Resources.t,
               events: [LifeCycleEvent.t],
               entry_point: {module, atom},
               health_index: float,
               vsn: any
             }

  defstruct [
    identifier: nil,
    master_node: true,
    time_stamp: nil,
    status: :offline,
    directive: :locked,
    services: nil,
    resources: nil,
    events: [],
    health_index: 0,
    entry_point: nil,
    vsn: @vsn
  ]
end

