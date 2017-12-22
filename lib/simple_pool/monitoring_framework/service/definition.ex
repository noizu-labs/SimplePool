#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.MonitoringFramework.Service.Definition do
  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               server: atom,
               supervisor: module,
               time_stamp: DateTime.t,
               hard_limit: integer,
               soft_limit: integer,
               target: integer,
               vsn: any
             }

  defstruct [
    identifier: nil,
    server: nil,
    supervisor: nil,
    time_stamp: nil,
    hard_limit: 0,
    soft_limit: 0,
    target: 0,
    vsn: @vsn
  ]
end

