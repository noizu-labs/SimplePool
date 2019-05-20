#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

use Amnesia

defdatabase Noizu.SimplePool.Database do
  #--------------------------------------
  # FastGlobal Cluster
  #--------------------------------------

  #--------------------------------------
  # Dispatch
  #--------------------------------------
  deftable DispatchTable, [:identifier, :server, :entity], type: :set, index: [] do
    @type t :: %DispatchTable{identifier: tuple, server: atom, entity: Noizu.SimplePool.DispatchEntity.t}
  end

  deftable Dispatch.MonitorTable, [:identifier, :time, :event, :details], type: :bag, index: [] do
    @type t :: %Dispatch.MonitorTable{identifier: any, time: integer, event: any, details: any}
  end

  #--------------------------------------
  # Monitoring Framework
  #--------------------------------------
  deftable MonitoringFramework.SettingTable, [:setting, :value], type: :bag, index: [] do
    @type t :: %MonitoringFramework.SettingTable{setting: atom, value: any}
  end

  deftable MonitoringFramework.NodeTable, [:identifier, :status, :directive, :health_index, :entity], type: :set, index: [] do
    @type t :: %MonitoringFramework.NodeTable{identifier: any, status: atom, directive: atom,  health_index: float, entity: Noizu.SimplePool.MonitoringFramework.Server.HealthCheck.t}
  end

  deftable MonitoringFramework.Node.EventTable, [:identifier, :event, :time_stamp, :entity], type: :bag, index: [] do
    @type t :: %MonitoringFramework.Node.EventTable{identifier: atom, event: atom, time_stamp: integer, entity: Noizu.SimplePool.MonitoringFramework.LifeCycleEvent.t}
  end

  deftable MonitoringFramework.ServiceTable, [:identifier, :status, :directive, :health_index, :entity], type: :set, index: [] do
    @type t :: %MonitoringFramework.ServiceTable{identifier: {atom, atom}, status: atom, directive: atom,  health_index: float, entity: Noizu.SimplePool.MonitoringFramework.Service.HealthCheck.t}
  end

  deftable MonitoringFramework.Service.EventTable, [:identifier, :event, :time_stamp, :entity], type: :bag, index: [] do
    @type t :: %MonitoringFramework.Service.EventTable{identifier: {atom, atom}, event: atom, time_stamp: integer, entity: Noizu.SimplePool.MonitoringFramework.LifeCycleEvent.t}
  end

  deftable MonitoringFramework.Service.HintTable, [:identifier, :hint, :time_stamp, :status], type: :set, index: [] do
    @type t :: %MonitoringFramework.Service.HintTable{identifier: atom, hint: Map.t, time_stamp: integer, status: atom}
  end

end
