ExUnit.start()

Amnesia.start

# Test Schema Setup
:ok = Noizu.SimplePool.Database.DispatchTable.create()
:ok = Noizu.SimplePool.Database.Dispatch.MonitorTable.create()

:ok = Noizu.SimplePool.Database.MonitoringFramework.SettingTable.create()
:ok = Noizu.SimplePool.Database.MonitoringFramework.NodeTable.create()
:ok = Noizu.SimplePool.Database.MonitoringFramework.ServiceTable.create()
:ok = Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable.create()

:ok = Noizu.SimplePool.Database.MonitoringFramework.Node.EventTable.create()
:ok = Noizu.SimplePool.Database.MonitoringFramework.Service.EventTable.create()













Application.ensure_all_started(:bypass)

Registry.start_link(keys: :unique, name: Noizu.SimplePool.DispatchRegister,  partitions: System.schedulers_online())

context = Noizu.ElixirCore.CallingContext.system(%{})






initial = %Noizu.SimplePool.MonitoringFramework.Server.HealthCheck{
  identifier: node(),
  master_node: true,
  time_stamp: DateTime.utc_now(),
  status: :offline,
  directive: :init,
  services: %{Noizu.SimplePool.Support.TestPool => %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{
    identifier: {node(), Noizu.SimplePool.Support.TestPool},
    time_stamp: DateTime.utc_now(),
    status: :offline,
    directive: :init,
    definition: %Noizu.SimplePool.MonitoringFramework.Service.Definition{
      identifier: {node(), Noizu.SimplePool.Support.TestPool},
      server: node(),
      pool: Noizu.SimplePool.Support.TestPool.Server,
      supervisor: Noizu.SimplePool.Support.TestPool.PoolSupervisor,
      time_stamp: DateTime.utc_now(),
      hard_limit: 200,
      soft_limit: 150,
      target: 100,
    },
  }},
  entry_point: :pending
}



#Noizu.EnvironmentManagerPool.PoolSupervisor.start_link(context)

#Noizu.EnvironmentManagerPool.Server.register(node(), initial, context)
#Noizu.EnvironmentManagerPool.Server.initialize(node(), context)

Noizu.MonitoringFramework.EnvironmentPool.PoolSupervisor.start_link(context, %Noizu.SimplePool.MonitoringFramework.Service.Definition{})
Noizu.MonitoringFramework.EnvironmentPool.Server.register(initial, context)
Noizu.MonitoringFramework.EnvironmentPool.Server.start_services(context)

s = Noizu.MonitoringFramework.EnvironmentPool.Server.status_wait([:online, :degraded], context)
IO.puts "STATE = #{inspect s}"