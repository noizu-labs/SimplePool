#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.MonitoringFramework.LifeCycleEvent do

  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               time_stamp: DateTime.t,
               details: any
             }

  defstruct [
    identifier: nil,
    time_stamp: nil,
    details: nil
  ]

end
