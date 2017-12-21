#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.Worker.HealthCheck do
  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               status: :online | :degraged | :critical | :offline,
               event_frequency: Map.t,
               check: float,
               events: list,
               vsn: any
             }

  defstruct [
    identifier: nil,
    status: :offline,
    event_frequency: %{},
    check: 0.0,
    events: [],
    vsn: @vsn
  ]
end
