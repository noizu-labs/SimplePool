ExUnit.start()

Amnesia.start
Noizu.SimplePool.Database.DispatchTable.create()
Noizu.SimplePool.Database.Dispatch.MonitorTable.create()

Application.ensure_all_started(:bypass)

Registry.start_link(keys: :unique, name: Noizu.SimplePool.DispatchRegister)

Noizu.SimplePool.Support.TestPool.PoolSupervisor.start_link
