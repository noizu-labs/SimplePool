#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Dispatch.MonitorRepo do
  use Noizu.SimplePool.DispatchMonitorRepoBehaviour,
    monitor_table: Noizu.SimplePool.Database.Dispatch.MonitorTable
end
