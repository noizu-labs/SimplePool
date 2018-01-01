defmodule Noizu.SimplePool.TestHelpers do
  def unique_ref(), do: {:ref, Noizu.SimplePool.Support.TestWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}
  def unique_ref(:two), do: {:ref, Noizu.SimplePool.Support.TestTwoWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}


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
          pool: Noizu.SimplePool.Support.TestPool.Server,
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
            pool: Noizu.SimplePool.Support.TestThreePool.Server,
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
              pool: Noizu.SimplePool.Support.TestTwoPool.Server,
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
              pool: Noizu.SimplePool.Support.TestThreePool.Server,
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