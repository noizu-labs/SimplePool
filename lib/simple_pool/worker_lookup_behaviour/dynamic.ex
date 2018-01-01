#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.WorkerLookupBehaviour.Dynamic do
  use Noizu.SimplePool.WorkerLookupBehaviour.DefaultImplementation,
      server_monitor: Noizu.MonitoringFramework.EnvironmentPool.Server



end