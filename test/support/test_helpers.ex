defmodule Noizu.SimplePool.TestHelpers do
  def unique_ref(), do: unique_ref(:one)
  def unique_ref(:one), do: {:ref, Noizu.SimplePool.Support.TestWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}
  def unique_ref(:two), do: {:ref, Noizu.SimplePool.Support.TestTwoWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}
  def unique_ref(:three), do: {:ref, Noizu.SimplePool.Support.TestThreeWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}

  def wait_hint_release(ref, service, context, timeout \\ 60_000) do
    t = :os.system_time(:millisecond)
    Process.sleep(100)
    case Noizu.SimplePool.WorkerLookupBehaviour.Dynamic.host!(ref, service, context) do
      {:ack, _h} -> :ok
      _j ->
        t2 = :os.system_time(:millisecond)
        t3 = timeout - (t2 - t)
        if t3 > 0 do
          wait_hint_release(ref, service, context, t3)
        else
          :timeout
        end

    end
  end

  def wait_hint_lock(ref, service, context, timeout \\ 60_000) do
    t = :os.system_time(:millisecond)
    Process.sleep(100)
    case Noizu.SimplePool.WorkerLookupBehaviour.Dynamic.host!(ref, service, context) do
      {:ack, _h} ->
        t2 = :os.system_time(:millisecond)
        t3 = timeout - (t2 - t)
        if t3 > 0 do
          wait_hint_lock(ref, service, context, t3)
        else
          :timeout
        end
      _j -> :ok
    end
  end

  def setup_first() do
    context = Noizu.ElixirCore.CallingContext.system(%{})
    Registry.start_link(keys: :unique, name: Noizu.SimplePool.DispatchRegister,  partitions: System.schedulers_online())
    initial = %Noizu.SimplePool.MonitoringFramework.Server.HealthCheck{
      identifier: node(),
      master_node: :self,
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
          pool: Noizu.SimplePool.Support.TestPool,
          service: Noizu.SimplePool.Support.TestPool.Server,
          supervisor: Noizu.SimplePool.Support.TestPool.PoolSupervisor,
          time_stamp: DateTime.utc_now(),
          hard_limit: 200,
          soft_limit: 150,
          target: 100,
        },
      },

        Noizu.SimplePool.Support.TestThreePool => %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{
          identifier: {node(), Noizu.SimplePool.Support.TestThreePool},
          time_stamp: DateTime.utc_now(),
          status: :offline,
          directive: :init,
          definition: %Noizu.SimplePool.MonitoringFramework.Service.Definition{
            identifier: {node(), Noizu.SimplePool.Support.TestThreePool},
            server: node(),
            pool: Noizu.SimplePool.Support.TestThreePool,
            service: Noizu.SimplePool.Support.TestThreePool.Server,
            supervisor: Noizu.SimplePool.Support.TestThreePool.PoolSupervisor,
            time_stamp: DateTime.utc_now(),
            hard_limit: 200,
            soft_limit: 150,
            target: 100,
          },
        }

      },
      entry_point: :pending
    }

    Noizu.MonitoringFramework.EnvironmentPool.PoolSupervisor.start_link(context, %Noizu.SimplePool.MonitoringFramework.Service.Definition{server_options: %{initial: initial}})
    {:ack, _} = Noizu.MonitoringFramework.EnvironmentPool.Server.register(initial, context)
    Noizu.MonitoringFramework.EnvironmentPool.Server.start_services(context)
    :online = Noizu.MonitoringFramework.EnvironmentPool.Server.status_wait([:online, :degraded], context)
  end

  def setup_second() do
    p = spawn fn ->


      IO.puts """
      =============== SETUP SECOND TEST NODE =====================
      node: #{node()}
      ============================================================
      """
      context = Noizu.ElixirCore.CallingContext.system(%{})

      Registry.start_link(keys: :unique, name: Noizu.SimplePool.DispatchRegister,  partitions: System.schedulers_online())

      initial = %Noizu.SimplePool.MonitoringFramework.Server.HealthCheck{
        identifier: node(),
        master_node: nil,
        time_stamp: DateTime.utc_now(),
        status: :offline,
        directive: :init,
        services: %{
          Noizu.SimplePool.Support.TestTwoPool => %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{
            identifier: {node(), Noizu.SimplePool.Support.TestTwoPool},
            time_stamp: DateTime.utc_now(),
            status: :offline,
            directive: :init,
            definition: %Noizu.SimplePool.MonitoringFramework.Service.Definition{
              identifier: {node(), Noizu.SimplePool.Support.TestTwoPool},
              server: node(),
              pool: Noizu.SimplePool.Support.TestTwoPool,
              service: Noizu.SimplePool.Support.TestTwoPool.Server,
              supervisor: Noizu.SimplePool.Support.TestTwoPool.PoolSupervisor,
              time_stamp: DateTime.utc_now(),
              hard_limit: 200,
              soft_limit: 150,
              target: 100,
            },
          },

          Noizu.SimplePool.Support.TestThreePool => %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{
            identifier: {node(), Noizu.SimplePool.Support.TestThreePool},
            time_stamp: DateTime.utc_now(),
            status: :offline,
            directive: :init,
            definition: %Noizu.SimplePool.MonitoringFramework.Service.Definition{
              identifier: {node(), Noizu.SimplePool.Support.TestThreePool},
              server: node(),
              pool: Noizu.SimplePool.Support.TestThreePool,
              service: Noizu.SimplePool.Support.TestThreePool.Server,
              supervisor: Noizu.SimplePool.Support.TestThreePool.PoolSupervisor,
              time_stamp: DateTime.utc_now(),
              hard_limit: 200,
              soft_limit: 150,
              target: 100,
            },
          }

        },
        entry_point: :pending
      }

      {:ok, _pid} = Noizu.MonitoringFramework.EnvironmentPool.PoolSupervisor.start_link(context, %Noizu.SimplePool.MonitoringFramework.Service.Definition{server_options: %{initial: initial}})
      {:ack, _} = Noizu.MonitoringFramework.EnvironmentPool.Server.register(nil, context)
      :ok = Noizu.MonitoringFramework.EnvironmentPool.Server.start_services(context)
      :online = Noizu.MonitoringFramework.EnvironmentPool.Server.status_wait([:online, :degraded], context)

      receive do
        :halt -> IO.puts "halting process"
      end
    end
    {:pid, p}
  end

end