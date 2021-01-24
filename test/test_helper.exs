#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

require Logger
Logger.info """

  ----------------------------------
  Test Start
  ----------------------------------
"""
ExUnit.start()

alias Noizu.SimplePool.Support.TestPool
alias Noizu.SimplePool.Support.TestTwoPool
#alias Noizu.SimplePool.Support.TestThreePool
Application.ensure_all_started(:bypass)
Application.ensure_all_started(:semaphore)



#-----------------------------------------------
# Test Schema Setup
#-----------------------------------------------
Amnesia.start



#-------------------------
# V1 Core Tables
#-------------------------
if !Amnesia.Table.exists?(Noizu.SimplePool.Database.DispatchTable) do
  :ok = Noizu.SimplePool.Database.DispatchTable.create()
  :ok = Noizu.SimplePool.Database.Dispatch.MonitorTable.create()
  :ok = Noizu.SimplePool.Database.MonitoringFramework.SettingTable.create()
  :ok = Noizu.SimplePool.Database.MonitoringFramework.NodeTable.create()
  :ok = Noizu.SimplePool.Database.MonitoringFramework.ServiceTable.create()
  :ok = Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable.create()

  :ok = Noizu.SimplePool.Database.MonitoringFramework.Node.EventTable.create()
  :ok = Noizu.SimplePool.Database.MonitoringFramework.Service.EventTable.create()
end


#-------------------------
# V2 Core Tables
#-------------------------
if !Amnesia.Table.exists?(Noizu.SimplePool.V2.Database.MonitoringFramework.SettingTable) do
  :ok = Noizu.SimplePool.V2.Database.MonitoringFramework.SettingTable.create()
  :ok = Noizu.SimplePool.V2.Database.MonitoringFramework.ConfigurationTable.create()
  :ok = Noizu.SimplePool.V2.Database.MonitoringFramework.NodeTable.create()
  :ok = Noizu.SimplePool.V2.Database.MonitoringFramework.ServiceTable.create()

  :ok = Noizu.SimplePool.V2.Database.MonitoringFramework.DetailedServiceEventTable.create()
  :ok = Noizu.SimplePool.V2.Database.MonitoringFramework.ServiceEventTable.create()
  :ok = Noizu.SimplePool.V2.Database.MonitoringFramework.DetailedServerEventTable.create()
  :ok = Noizu.SimplePool.V2.Database.MonitoringFramework.ServerEventTable.create()
  :ok = Noizu.SimplePool.V2.Database.MonitoringFramework.ClusterEventTable.create()
end

#-------------------------
# V2.B Core Tables
#-------------------------
if !Amnesia.Table.exists?(Noizu.SimplePool.V2.Database.Cluster.Service.Instance.StateTable) do
  IO.puts "SETUP V2.B Tables"
  :ok = Noizu.SimplePool.V2.Database.Cluster.SettingTable.create()
  :ok = Noizu.SimplePool.V2.Database.Cluster.StateTable.create()
  :ok = Noizu.SimplePool.V2.Database.Cluster.TaskTable.create()
  :ok = Noizu.SimplePool.V2.Database.Cluster.Service.StateTable.create()
  :ok = Noizu.SimplePool.V2.Database.Cluster.Service.WorkerTable.create()
  :ok = Noizu.SimplePool.V2.Database.Cluster.Service.TaskTable.create()
  :ok = Noizu.SimplePool.V2.Database.Cluster.Service.Instance.StateTable.create()
  :ok = Noizu.SimplePool.V2.Database.Cluster.Node.StateTable.create()
  :ok = Noizu.SimplePool.V2.Database.Cluster.Node.WorkerTable.create()
  :ok = Noizu.SimplePool.V2.Database.Cluster.Node.TaskTable.create()
end




#---------------------
# Test Pool: Dispatch Tables
#---------------------
if !Amnesia.Table.exists?(Noizu.SimplePool.TestDatabase.TestV2Pool.DispatchTable) do
  :ok = Noizu.SimplePool.TestDatabase.TestV2Pool.DispatchTable.create()
end
if !Amnesia.Table.exists?(Noizu.SimplePool.TestDatabase.TestV2TwoPool.DispatchTable) do
  :ok = Noizu.SimplePool.TestDatabase.TestV2TwoPool.DispatchTable.create()
end
if !Amnesia.Table.exists?(Noizu.SimplePool.TestDatabase.TestV2ThreePool.DispatchTable) do
  :ok = Noizu.SimplePool.TestDatabase.TestV2ThreePool.DispatchTable.create()
end


:ok = Amnesia.Table.wait(Noizu.SimplePool.Database.tables(), 5_000)
:ok = Amnesia.Table.wait(Noizu.SimplePool.TestDatabase.tables(), 5_000)

# Wait for second node
connected = Node.connect(:"second@127.0.0.1")
if (!connected) do
  IO.puts "Waiting five minutes for second test node (./test-node.sh)"
  case Noizu.SimplePool.TestHelpers.wait_for_condition(fn() -> (Node.connect(:"second@127.0.0.1") == true) end, 60 * 5) do
    :ok ->
      IO.puts "Second Node Online"
    {:error, :timeout} ->
      IO.puts "Timeout Occurred waiting for Second Node"
      exit(:shutdown)
  end
end

# Wait for connectivity / compile
Noizu.SimplePool.TestHelpers.wait_for_condition(
  fn() ->
    :rpc.call(:"second@127.0.0.1", Noizu.SimplePool.TestHelpers, :wait_for_init, []) == :ok
  end,
  60 * 5
)

spawn_second = if !Enum.member?(Amnesia.info(:db_nodes),:"second@127.0.0.1") do
    # conditional include to reduce the need to restart the remote server
    IO.puts "SPAWN SECOND == true"
    :mnesia.change_config(:extra_db_nodes, [:"second@127.0.0.1"])
    true
  else
    IO.puts "SPAWN SECOND == false"
    false
  end

:ok = :rpc.call(:"second@127.0.0.1", Noizu.SimplePool.TestHelpers, :wait_for_db, [])

#-----------------------------------------------
# Registry and Environment Manager Setup - Local
#-----------------------------------------------
context = Noizu.ElixirCore.CallingContext.system(%{})
Noizu.SimplePool.TestHelpers.setup_first()
:ok = Noizu.SimplePool.TestHelpers.unique_ref(:one)
      |> Noizu.SimplePool.TestHelpers.wait_hint_release(TestPool.Server, context)

if spawn_second do
  IO.puts "Provision Second Node for Test"
  {:pid, _second_pid} = :rpc.call(:"second@127.0.0.1", Noizu.SimplePool.TestHelpers, :setup_second, [])
else
  IO.puts "Checking second node state"
  case :rpc.call(:"second@127.0.0.1", Noizu.MonitoringFramework.EnvironmentPool.Server, :node_health_check!, [context, %{}]) do
    {:badrpc, _} ->
      {:pid, _second_pid} = :rpc.call(:"second@127.0.0.1", Noizu.SimplePool.TestHelpers, :setup_second, [])
    v -> IO.puts "Checking second node state #{inspect v}"
  end
end

IO.puts "Wait For Hint Release"
:ok = Noizu.SimplePool.TestHelpers.unique_ref(:two)
      |> Noizu.SimplePool.TestHelpers.wait_hint_release(TestTwoPool.Server, context)

IO.puts "Wait For Hint Release . . . [PROCEED]"

if (node() == :"first@127.0.0.1") do
  IO.puts "//////////////////////////////////////////////////////"
  IO.puts "waiting for TestV2Two to come online"
  IO.puts "//////////////////////////////////////////////////////"
  # Wait for connectivity / compile
  Noizu.SimplePool.TestHelpers.wait_for_condition(
    fn() ->
      :rpc.call(:"second@127.0.0.1", Noizu.SimplePool.Support.TestV2TwoPool.Server, :server_online?, []) == true
    end,
    60 * 5
  )

  IO.puts "//////////////////////////////////////////////////////"
  IO.puts "waiting for remote registry"
  IO.puts "//////////////////////////////////////////////////////"

  :ok = Noizu.SimplePool.TestHelpers.wait_for_condition(
    fn() ->
      :rpc.call(:"second@127.0.0.1", Registry, :lookup, [Noizu.SimplePool.Support.TestV2TwoPool.Registry, {:worker, :aple}]) == []
    end,
    60 * 5
  )
  [] = :rpc.call(:"second@127.0.0.1", Registry, :lookup, [Noizu.SimplePool.Support.TestV2TwoPool.Registry, {:worker, :aple}])



  IO.puts "//////////////////////////////////////////////////////"
  IO.puts "Proceed"
  IO.puts "//////////////////////////////////////////////////////"

end
