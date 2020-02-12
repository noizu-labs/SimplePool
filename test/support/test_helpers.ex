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


  #-------------------------
  # Helper Method
  #-------------------------
  def wait_for_db() do
    wait_for_condition(
      fn() ->
        Enum.member?(Amnesia.info(:running_db_nodes), :"second@127.0.0.1") && Enum.member?(Amnesia.info(:running_db_nodes), :"first@127.0.0.1")
      end,
      60 * 5)
  end

  def wait_for_init() do
    Amnesia.start
    r = wait_for_condition(
      fn() ->
        Enum.member?(Amnesia.info(:running_db_nodes), :"second@127.0.0.1")
      end,
      60 * 5)
  end

  def wait_for_condition(condition, timeout \\ :infinity) do
    cond do
      !is_function(condition, 0) -> {:error, :condition_not_callable}
      is_integer(timeout) -> wait_for_condition_inner(condition, :os.system_time(:seconds) + timeout)
      timeout == :infinity -> wait_for_condition_inner(condition, timeout)
      true ->  {:error, :invalid_timeout}
    end
  end

  def wait_for_condition_inner(condition, timeout) do
    check = condition.()
    cond do
      check == :ok || check == true -> :ok
      is_integer(timeout) && timeout < :os.system_time(:seconds) -> {:error, :timeout}
      true ->
        Process.sleep(100)
        wait_for_condition_inner(condition, timeout)
    end
  end



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





  def configure_test_cluster_old(context, telemetry_handler, event_handler) do

    telemetry_handler = nil
    event_handler = nil


    #----------------------------------------------------------------
    # Populate Service and Instance Configuration
    #----------------------------------------------------------------

    #-------------------------------------
    # test_service_one
    #-------------------------------------
    service = Noizu.SimplePool.Support.TestV2Pool
    test_service_one = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Definition.new(service, %{min: 1, max: 3, target: 2}, %{min: 1, max: 3, target: 2})
    test_service_one_status = %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Status{
      service: service,
      instances: %{
        :"first@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Status.new(service, :"first@127.0.0.1", nil, nil),
        :"second@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Status.new(service, :"second@127.0.0.1", nil, nil),
      },
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
    }
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity{
      identifier: service,
      service_definition: test_service_one,
      status_details: test_service_one_status,
      instance_definitions: %{
        :"first@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Definition.new(service, :"first@127.0.0.1", %{min: 1, max: 3, target: 2}, 1.0),
        :"second@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Definition.new(service, :"second@127.0.0.1", %{min: 1, max: 3, target: 2}, 0.5)
      },
      instance_statuses: %{}, # pending
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
      telemetry_handler: telemetry_handler,
      event_handler: event_handler,
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.create!(context)

    #-------------------------------------
    # test_service_two
    #-------------------------------------
    service = Noizu.SimplePool.Support.TestV2TwoPool
    test_service_two = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Definition.new(service, %{min: 1, max: 3, target: 2}, %{min: 1, max: 3, target: 2})
    test_service_two_status = %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Status{
      service: service,
      instances: %{
        :"second@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Status.new(service, :"second@127.0.0.1", nil, nil),
      },
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
    }
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity{
      identifier: service,
      service_definition: test_service_one,
      status_details: test_service_one_status,
      instance_definitions: %{
        :"second@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Definition.new(service, :"second@127.0.0.1", %{min: 1, max: 3, target: 2}, 0.5)
      },
      instance_statuses: %{}, # pending
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
      telemetry_handler: telemetry_handler,
      event_handler: event_handler,
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.create!(context)

    #-------------------------------------
    # test_service_three
    #-------------------------------------
    service = Noizu.SimplePool.Support.TestV2ThreePool
    test_service_three = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Definition.new(service, %{min: 1, max: 3, target: 2}, %{min: 1, max: 3, target: 2})
    test_service_three_status = %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Status{
      service: service,
      instances: %{
        :"first@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Status.new(service, :"first@127.0.0.1", nil, nil),
      },
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
    }
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity{
      identifier: service,
      service_definition: test_service_three,
      status_details: test_service_three_status,
      instance_definitions: %{
        :"first@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Definition.new(service, :"first@127.0.0.1", %{min: 1, max: 3, target: 2}, 1.0),
      },
      instance_statuses: %{}, # pending
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
      telemetry_handler: telemetry_handler,
      event_handler: event_handler,
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.create!(context)

    #----------------------------------------------------------------
    # Node Manager Definitions
    #----------------------------------------------------------------
    cluster_node = :"first@127.0.0.1"
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateEntity{
      identifier: cluster_node,
      node_definition: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Definition.new(cluster_node, %{low: 0, high: 1000, target: 500}, %{low: 0.0, high: 85.0, target: 70.0}, %{low: 0.0, high: 85.0, target: 70.0}, %{low: 0.0, high: 85.0, target: :none}, 1.0),
      status_details: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Status.new(cluster_node ),
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateEntity, cluster_node }),
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateRepo.create!(context)

    cluster_node = :"second@127.0.0.1"
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateEntity{
      identifier: cluster_node,
      node_definition: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Definition.new(cluster_node, %{low: 0, high: 1000, target: 500}, %{low: 0.0, high: 85.0, target: 70.0}, %{low: 0.0, high: 85.0, target: 70.0}, %{low: 0.0, high: 85.0, target: :none}, 1.0),
      status_details: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Status.new(cluster_node ),
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateEntity, cluster_node }),
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateRepo.create!(context)

    #----------------------------------------------------------------
    # Populate Cluster Configuration
    #----------------------------------------------------------------
    service_definitions = %{
      Noizu.SimplePool.Support.TestV2Pool => test_service_one,
      Noizu.SimplePool.Support.TestV2TwoPool => test_service_two,
      Noizu.SimplePool.Support.TestV2ThreePool => test_service_three,
    }
    service_statuses = %{
      Noizu.SimplePool.Support.TestV2Pool => test_service_one_status,
      Noizu.SimplePool.Support.TestV2TwoPool => test_service_two_status,
      Noizu.SimplePool.Support.TestV2ThreePool => test_service_three_status,
    }
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity{
      identifier: :default_cluster,
      cluster_definition: Noizu.SimplePool.V2.ClusterManagement.Cluster.Definition.new(:default_cluster),
      service_definitions: service_definitions,
      service_statuses: service_statuses,
      status_details: Noizu.SimplePool.V2.ClusterManagement.Cluster.Status.new(:default_cluster),
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity, :default_cluster}),
      telemetry_handler: telemetry_handler,
      event_handler: event_handler,
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.create!(context)

    :ok
  end

  def configure_test_cluster(context, telemetry_handler, event_handler) do

    telemetry_handler = nil
    event_handler = nil


    #----------------------------------------------------------------
    # Populate Service and Instance Configuration
    #----------------------------------------------------------------

    #-------------------------------------
    # test_service_one
    #-------------------------------------
    service = Noizu.SimplePool.Support.TestV2Pool
    test_service_one = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Definition.new(service, %{min: 1, max: 3, target: 2}, %{min: 1, max: 3, target: 2})
    test_service_one_status = %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Status{
      service: service,
      instances: %{
        :"first@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Status.new(service, :"first@127.0.0.1", nil, nil),
        :"second@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Status.new(service, :"second@127.0.0.1", nil, nil),
      },
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
    }
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity{
      identifier: service,
      service_definition: test_service_one,
      status_details: test_service_one_status,
      instance_definitions: %{
        :"first@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Definition.new(service, :"first@127.0.0.1", %{min: 1, max: 3, target: 2}, 1.0),
        :"second@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Definition.new(service, :"second@127.0.0.1", %{min: 1, max: 3, target: 2}, 0.5)
      },
      instance_statuses: %{}, # pending
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
      telemetry_handler: telemetry_handler,
      event_handler: event_handler,
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.create!(context)

    #-------------------------------------
    # test_service_two
    #-------------------------------------
    service = Noizu.SimplePool.Support.TestV2TwoPool
    test_service_two = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Definition.new(service, %{min: 1, max: 3, target: 2}, %{min: 1, max: 3, target: 2})
    test_service_two_status = %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Status{
      service: service,
      instances: %{
        :"second@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Status.new(service, :"second@127.0.0.1", nil, nil),
      },
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
    }
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity{
      identifier: service,
      service_definition: test_service_one,
      status_details: test_service_one_status,
      instance_definitions: %{
        :"second@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Definition.new(service, :"second@127.0.0.1", %{min: 1, max: 3, target: 2}, 0.5)
      },
      instance_statuses: %{}, # pending
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
      telemetry_handler: telemetry_handler,
      event_handler: event_handler,
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.create!(context)

    #-------------------------------------
    # test_service_three
    #-------------------------------------
    service = Noizu.SimplePool.Support.TestV2ThreePool
    test_service_three = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Definition.new(service, %{min: 1, max: 3, target: 2}, %{min: 1, max: 3, target: 2})
    test_service_three_status = %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Status{
      service: service,
      instances: %{
        :"first@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Status.new(service, :"first@127.0.0.1", nil, nil),
      },
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
    }
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity{
      identifier: service,
      service_definition: test_service_three,
      status_details: test_service_three_status,
      instance_definitions: %{
        :"first@127.0.0.1" => Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.Instance.Definition.new(service, :"first@127.0.0.1", %{min: 1, max: 3, target: 2}, 1.0),
      },
      instance_statuses: %{}, # pending
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity, service}),
      telemetry_handler: telemetry_handler,
      event_handler: event_handler,
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.create!(context)

    #----------------------------------------------------------------
    # Node Manager Definitions
    #----------------------------------------------------------------
    cluster_node = :"first@127.0.0.1"
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateEntity{
      identifier: cluster_node,
      node_definition: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Definition.new(cluster_node, %{low: 0, high: 1000, target: 500}, %{low: 0.0, high: 85.0, target: 70.0}, %{low: 0.0, high: 85.0, target: 70.0}, %{low: 0.0, high: 85.0, target: :none}, 1.0),
      status_details: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Status.new(cluster_node ),
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateEntity, cluster_node }),
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateRepo.create!(context)

    cluster_node = :"second@127.0.0.1"
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateEntity{
      identifier: cluster_node,
      node_definition: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Definition.new(cluster_node, %{low: 0, high: 1000, target: 500}, %{low: 0.0, high: 85.0, target: 70.0}, %{low: 0.0, high: 85.0, target: 70.0}, %{low: 0.0, high: 85.0, target: :none}, 1.0),
      status_details: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Status.new(cluster_node ),
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateEntity, cluster_node }),
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateRepo.create!(context)

    #----------------------------------------------------------------
    # Populate Cluster Configuration
    #----------------------------------------------------------------
    service_definitions = %{
      Noizu.SimplePool.Support.TestV2Pool => test_service_one,
      Noizu.SimplePool.Support.TestV2TwoPool => test_service_two,
      Noizu.SimplePool.Support.TestV2ThreePool => test_service_three,
    }
    service_statuses = %{
      Noizu.SimplePool.Support.TestV2Pool => test_service_one_status,
      Noizu.SimplePool.Support.TestV2TwoPool => test_service_two_status,
      Noizu.SimplePool.Support.TestV2ThreePool => test_service_three_status,
    }
    %Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity{
      identifier: :default_cluster,
      cluster_definition: Noizu.SimplePool.V2.ClusterManagement.Cluster.Definition.new(:default_cluster),
      service_definitions: service_definitions,
      service_statuses: service_statuses,
      status_details: Noizu.SimplePool.V2.ClusterManagement.Cluster.Status.new(:default_cluster),
      health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.new({:ref, Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity, :default_cluster}),
      telemetry_handler: telemetry_handler,
      event_handler: event_handler,
    } |> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.create!(context)

    :ok
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



    #=================================================================
    # Cluster Manager
    #=================================================================
    telemetry_handler = nil
    event_handler = nil


    # Setup Cluster Configuration
    configure_test_cluster(context, telemetry_handler, event_handler)

    # Bring Cluster Online
    #Noizu.SimplePool.V2.ClusterManagementFramework.ClusterManager.start(%{}, context)
    #Noizu.SimplePool.V2.ClusterManagementFramework.ClusterManager.bring_cluster_online(%{}, context)


    # Bring Node (And Appropriate Services) Online - this will spawn actual Service Instances, ClusterManager will bring on service managers if not already online.
    Noizu.SimplePool.V2.ClusterManagementFramework.Cluster.NodeManager.start({:"first@127.0.0.1", %{}}, context)
    Noizu.SimplePool.V2.ClusterManagementFramework.Cluster.NodeManager.bring_node_online(:"first@127.0.0.1", %{}, context)

    # Wait for node to register online
    Noizu.SimplePool.V2.ClusterManagementFramework.Cluster.NodeManager.block_for_state(:"first@127.0.0.1", :online, context, 30_000)
    #Noizu.SimplePool.V2.ClusterManagementFramework.Cluster.NodeManager.block_for_state(:"second@127.0.0.1", :online, context, 30_000)
    case Noizu.SimplePool.V2.ClusterManagementFramework.Cluster.NodeManager.block_for_status(:"first@127.0.0.1", [:green, :degraded], context, 30_000) do
      {:ok, s} ->
        Logger.info("""
        ================================================================
        !!! Test Cluster Services: :"first@126.0.0.1"  # {inspect s} !!!
        ================================================================
        """)

      e ->
      Logger.error("""
      ================================================================
      !!! Unable to bring system fully online: :"first@126.0.0.1" # {inspect e} !!!
      ================================================================
      """)
      e
    end


:ok

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


      # Bring Node (And Appropriate Services) Online - this will spawn actual Service Instances, ClusterManager will bring on service managers if not already online.
      Noizu.SimplePool.V2.ClusterManagementFramework.Cluster.NodeManager.start({:"second@127.0.0.1", %{}}, context)
      Noizu.SimplePool.V2.ClusterManagementFramework.Cluster.NodeManager.bring_node_online(:"second@127.0.0.1", %{}, context)
      case Noizu.SimplePool.V2.ClusterManagementFramework.Cluster.NodeManager.block_for_status(:"second@127.0.0.1", [:green, :degraded], context, 30_000) do
        {:ok, s} ->
          Logger.info("""
          ================================================================
          !!! Test Cluster Services:  # {inspect s} !!!
          ================================================================
          """)

        e ->
          Logger.error("""
          ================================================================
          !!! Unable to bring system fully online:  # {inspect e} !!!
          ================================================================
          """)
          e
      end


      receive do
        :halt -> IO.puts "halting process"
      end
    end
    {:pid, p}
  end
end
