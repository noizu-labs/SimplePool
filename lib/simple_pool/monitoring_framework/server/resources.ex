#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.MonitoringFramework.Server.Resources do

  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               time_stamp: DateTime.t,
               cpu: %{nproc: integer, load: %{1 => float, 5 => float, 15 => float, 30 => float}},
               ram: %{total: float, allocated: float},
               vsn: any
             }

  defstruct [
    identifier: nil,
    time_stamp: nil,
    cpu: %{nproc: 0, load: %{1 => 0.0, 5 => 0.0, 15 => 0.0, 30 => 0.0}},
    ram: %{total: 0.0, allocated: 0.0},
    vsn: @vsn
  ]

end


