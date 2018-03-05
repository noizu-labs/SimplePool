#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Support.Schema.Core do
  alias Noizu.MnesiaVersioning.ChangeSet
  use Amnesia
  use Noizu.SimplePool.Database
  use Noizu.MnesiaVersioning.SchemaBehaviour


  def neighbors() do
    topology_provider = Application.get_env(:noizu_mnesia_versioning, :topology_provider)
    {:ok, nodes} = topology_provider.mnesia_nodes();
    nodes
  end

  #-----------------------------------------------------------------------------
  # ChangeSets
  #-----------------------------------------------------------------------------
  def change_sets do
    [
      %ChangeSet{
        changeset:  "Supporting Tables for Default Implementation",
        author: "Keith Brings",
        note: "Test Data",
        environments: [:test, :dev],
        update: fn() ->
                  neighbors = neighbors()
                  create_table(Noizu.SimplePool.Database.DispatchTable, [memory: neighbors])

                  create_table(Noizu.SimplePool.Database.Dispatch.MonitorTable, [memory: neighbors])

                  create_table(Noizu.SimplePool.Database.MonitoringFramework.SettingTable, [memory: neighbors])
                  create_table(Noizu.SimplePool.Database.MonitoringFramework.NodeTable, [memory: neighbors])
                  create_table(Noizu.SimplePool.Database.MonitoringFramework.Node.EventTable, [memory: neighbors])
                  create_table(Noizu.SimplePool.Database.MonitoringFramework.ServiceTable, [memory: neighbors])
                  create_table(Noizu.SimplePool.Database.MonitoringFramework.Service.EventTable, [memory: neighbors])
                  create_table(Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable, [memory: neighbors])

                  :success
        end,
        rollback: fn() ->
          destroy_table(Noizu.SimplePool.Database.DispatchTable)
          destroy_table(Noizu.SimplePool.Database.Dispatch.MonitorTable)

          destroy_table(Noizu.SimplePool.Database.MonitoringFramework.SettingTable)
          destroy_table(Noizu.SimplePool.Database.MonitoringFramework.NodeTable)
          destroy_table(Noizu.SimplePool.Database.MonitoringFramework.Node.EventTable)
          destroy_table(Noizu.SimplePool.Database.MonitoringFramework.ServiceTable)
          destroy_table(Noizu.SimplePool.Database.MonitoringFramework.Service.EventTable)
          destroy_table(Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable)
          :removed
        end
      }
    ]
  end
end
