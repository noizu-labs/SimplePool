#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
use Amnesia

defdatabase Noizu.SimplePool.Database do
  deftable DispatchTable, [:identifier, :server, :entity], type: :set, index: [] do
    @type t :: %DispatchTable{identifier: tuple, server: atom, entity: Noizu.SimplePool.DispatchEntity.t}
  end

  deftable Dispatch.MonitorTable, [:identifier, :time, :event, :details], type: :bag, index: [] do
    @type t :: %Dispatch.MonitorTable{identifier: any, time: integer, event: any, details: any}
  end
end