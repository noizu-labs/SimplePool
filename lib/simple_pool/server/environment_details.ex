#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Server.EnvironmentDetails do
  alias Noizu.SimplePool.Server.EnvironmentDetails

  @type t :: %__MODULE__{
               server: any,
               definition: any,
               initial: Noizu.SimplePool.MonitoringFramework.Service.HealthCheck.t,
               effective: Noizu.SimplePool.MonitoringFramework.Service.HealthCheck.t,
               default: any,
               status: atom,
               monitors: Map.t,
             }

  defstruct [
    server: nil,
    definition: nil,
    initial: nil,
    effective: nil,
    default: nil,
    status: nil,
    monitors: %{}
  ]

end
