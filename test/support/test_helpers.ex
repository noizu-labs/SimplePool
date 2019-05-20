#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.TestHelpers do
  def unique_ref(), do: unique_ref(:one)
  def unique_ref(:one), do: {:ref, Noizu.SimplePool.Support.TestWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}
  def unique_ref(:two), do: {:ref, Noizu.SimplePool.Support.TestTwoWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}
  def unique_ref(:three), do: {:ref, Noizu.SimplePool.Support.TestThreeWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}

  def unique_ref_v2(:one), do: {:ref, Noizu.SimplePool.Support.TestV2WorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}
  def unique_ref_v2(:two), do: {:ref, Noizu.SimplePool.Support.TestV2TwoWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}
  def unique_ref_v2(:three), do: {:ref, Noizu.SimplePool.Support.TestV2ThreeWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}

  require Logger
  @pool_options %{hard_limit: 250, soft_limit: 150, target: 100}

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
      services: %{
        Noizu.SimplePool.Support.TestPool =>
          Noizu.SimplePool.MonitoringFramework.Service.HealthCheck.template(Noizu.SimplePool.Support.TestPool, @pool_options),

        Noizu.SimplePool.Support.TestThreePool =>
          Noizu.SimplePool.MonitoringFramework.Service.HealthCheck.template(Noizu.SimplePool.Support.TestThreePool, @pool_options),

      },
      entry_point: :pending
    }

    # Start Legacy V1
    Noizu.MonitoringFramework.EnvironmentPool.PoolSupervisor.start_link(context, %Noizu.SimplePool.MonitoringFramework.Service.Definition{server_options: %{initial: initial}})
    {:ack, _} = Noizu.MonitoringFramework.EnvironmentPool.Server.register(initial, context)
    Noizu.MonitoringFramework.EnvironmentPool.Server.start_services(context)
    :online = Noizu.MonitoringFramework.EnvironmentPool.Server.status_wait([:online, :degraded], context)

    # Start V2 Monitor
    monitor_name = {:default, node()}
    Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor.start(monitor_name, context)

    # - Set Temporary Pool Configuration
    test_v2_pool = Noizu.SimplePool.V2.MonitoringFramework.ServiceMonitorConfiguration.new(Noizu.SimplePool.Support.TestV2Pool)
    test_v2_three_pool = Noizu.SimplePool.V2.MonitoringFramework.ServiceMonitorConfiguration.new(Noizu.SimplePool.Support.TestV2ThreePool)
    v2_config = Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration.new(monitor_name)
                |> Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration.add_service(test_v2_pool)
                |> Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration.add_service(test_v2_three_pool)

    Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor.reconfigure(v2_config, context, %{persist: false})
    Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor.bring_services_online(context)
    status = Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor.status_wait([:online, :degraded], context)
    case status do
      e = {:error, details} ->

      Logger.error("""

      ================================================================
      !!! Unable to bring system fully online:  #{inspect details} !!!
      ================================================================
      """)
      e
      _ -> status
    end
  end

  def setup_second() do

    Application.ensure_all_started(:semaphore)

    IO.puts """
    =============== SETUP SECOND TEST NODE =====================
    node: #{node()}
    semaphore_test: #{inspect :rpc.call(node(), Semaphore, :acquire, [:test, 5])}
    ============================================================
    """

    p = spawn fn ->




      :ok = Amnesia.Table.wait(Noizu.SimplePool.Database.tables(), 5_000)

      context = Noizu.ElixirCore.CallingContext.system(%{})

      Registry.start_link(keys: :unique, name: Noizu.SimplePool.DispatchRegister,  partitions: System.schedulers_online())

      initial = %Noizu.SimplePool.MonitoringFramework.Server.HealthCheck{
        identifier: node(),
        master_node: nil,
        time_stamp: DateTime.utc_now(),
        status: :offline,
        directive: :init,
        services: %{
          Noizu.SimplePool.Support.TestTwoPool =>
            Noizu.SimplePool.MonitoringFramework.Service.HealthCheck.template(Noizu.SimplePool.Support.TestTwoPool, @pool_options),
          Noizu.SimplePool.Support.TestThreePool =>
            Noizu.SimplePool.MonitoringFramework.Service.HealthCheck.template(Noizu.SimplePool.Support.TestThreePool, @pool_options),
        },
        entry_point: :pending
      }

      {:ok, _pid} = Noizu.MonitoringFramework.EnvironmentPool.PoolSupervisor.start_link(context, %Noizu.SimplePool.MonitoringFramework.Service.Definition{server_options: %{initial: initial}})
      {:ack, _} = Noizu.MonitoringFramework.EnvironmentPool.Server.register(nil, context)
      :ok = Noizu.MonitoringFramework.EnvironmentPool.Server.start_services(context)
      :online = Noizu.MonitoringFramework.EnvironmentPool.Server.status_wait([:online, :degraded], context)




      # Start V2 Monitor
      monitor_name = {:default, node()}
      Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor.start(monitor_name, context)

      # - Set Temporary Pool Configuration
      test_v2_pool = Noizu.SimplePool.V2.MonitoringFramework.ServiceMonitorConfiguration.new(Noizu.SimplePool.Support.TestV2Pool)
      test_v2_two_pool = Noizu.SimplePool.V2.MonitoringFramework.ServiceMonitorConfiguration.new(Noizu.SimplePool.Support.TestV2TwoPool)
      v2_config = Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration.new(monitor_name)
                  |> Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration.add_service(test_v2_pool)
                  |> Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration.add_service(test_v2_two_pool)

      Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor.reconfigure(v2_config, context, %{persist: false})
      Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor.bring_services_online(context)
      status = Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor.status_wait([:online, :degraded], context)
      case status do
        e = {:error, details} ->

          Logger.error("""

          ================================================================
          !!! Unable to bring system fully online:  #{inspect details} !!!
          ================================================================
          """)
          e
        _ -> status
      end

      receive do
        :halt -> IO.puts "halting process"
      end
    end
    {:pid, p}
  end
end
