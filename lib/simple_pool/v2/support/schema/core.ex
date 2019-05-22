#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Support.Schema.Core do
  alias Noizu.MnesiaVersioning.ChangeSet
  use Amnesia
  use Noizu.SimplePool.V2.Database
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
        note: "SimplePool V2 Core Tables",
        environments: [:test, :dev],
        update: fn() ->
                  neighbors = neighbors()
                  create_table(Database.MonitoringFramework.SettingTable, [disk: neighbors])
                  create_table(Database.MonitoringFramework.ConfigurationTable, [disk: neighbors])
                  create_table(Database.MonitoringFramework.NodeTable, [disk: neighbors])
                  create_table(Database.MonitoringFramework.ServiceTable, [disk: neighbors])

                  create_table(Database.MonitoringFramework.DetailedServiceEventTable, [disk: neighbors])
                  create_table(Database.MonitoringFramework.ServiceEventTable, [disk: neighbors])
                  create_table(Database.MonitoringFramework.DetailedServerEventTable, [disk: neighbors])
                  create_table(Database.MonitoringFramework.ServerEventTable, [disk: neighbors])
                  create_table(Database.MonitoringFramework.ClusterEventTable, [disk: neighbors])
                  :success
        end,
        rollback: fn() ->
          destroy_table(Database.MonitoringFramework.SettingTable)
          destroy_table(Database.MonitoringFramework.ConfigurationTable)
          destroy_table(Database.MonitoringFramework.NodeTable)
          destroy_table(Database.MonitoringFramework.ServiceTable)

          destroy_table(Database.MonitoringFramework.DetailedServiceEventTable)
          destroy_table(Database.MonitoringFramework.ServiceEventTable)
          destroy_table(Database.MonitoringFramework.DetailedServerEventTable)
          destroy_table(Database.MonitoringFramework.ServerEventTable)
          destroy_table(Database.MonitoringFramework.ClusterEventTable)
          :removed
        end
      }
    ]
  end
end
