ExUnit.start()



Application.ensure_all_started(:bypass)


#-----------------------------------------------
# Test Schema Setup
#-----------------------------------------------
Amnesia.start
:ok = Noizu.SimplePool.Database.DispatchTable.create()
:ok = Noizu.SimplePool.Database.Dispatch.MonitorTable.create()

:ok = Noizu.SimplePool.Database.MonitoringFramework.SettingTable.create()
:ok = Noizu.SimplePool.Database.MonitoringFramework.NodeTable.create()
:ok = Noizu.SimplePool.Database.MonitoringFramework.ServiceTable.create()
:ok = Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable.create()

:ok = Noizu.SimplePool.Database.MonitoringFramework.Node.EventTable.create()
:ok = Noizu.SimplePool.Database.MonitoringFramework.Service.EventTable.create()

Node.connect(:"second@127.0.0.1")
:rpc.call(:"second@127.0.0.1", Amnesia, :start, [])
{:ok, [:"second@127.0.0.1"]} = :mnesia.change_config(:extra_db_nodes, [:"second@127.0.0.1"])


#-----------------------------------------------
# Registry and Environment Manager Setup - Local
#-----------------------------------------------
Noizu.SimplePool.TestHelpers.setup_first()
IO.puts "c"
:rpc.call(:"second@127.0.0.1", Noizu.SimplePool.TestHelpers, :setup_second, [])
IO.puts "d"