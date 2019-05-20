#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

use Amnesia

defdatabase Noizu.SimplePool.V2.Database do

  #--------------------------------------
  # Monitoring Framework
  #--------------------------------------
  deftable MonitoringFramework.SettingTable, [:setting, :value], type: :bag, index: [] do
    @type t :: %MonitoringFramework.SettingTable{setting: atom, value: any}
  end

  deftable MonitoringFramework.ConfigurationTable, [:identifier, :entity], type: :set, index: [] do
    @type t :: %MonitoringFramework.ConfigurationTable{identifier: any, entity: any}
  end

  deftable MonitoringFramework.NodeTable, [:identifier, :status, :directive, :health_index, :entity], type: :set, index: [] do
    @type t :: %MonitoringFramework.NodeTable{identifier: any, status: atom, directive: atom,  health_index: float, entity: any}
  end

  deftable MonitoringFramework.ServiceTable, [:identifier, :status, :directive, :health_index, :entity], type: :set, index: [] do
    @type t :: %MonitoringFramework.ServiceTable{identifier: {atom, atom}, status: atom, directive: atom,  health_index: float, entity: any}
  end

end