#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
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
          :success
        end,
        rollback: fn() ->
          destroy_table(Noizu.SimplePool.Database.DispatchTable)
          destroy_table(Noizu.SimplePool.Database.Dispatch.MonitorTable)
          :removed
        end
      }
    ]
  end
end