#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule Noizu.SimplePool.V2.ClusterManagementFramework.ClusterManager do
  @moduledoc """
     The cluster manager is responsible for monitoring multiple services spanning multiple nodes and provides the entry point for grabbing current cluster status info.
  """

  use Noizu.SimplePool.V2.StandAloneServiceBehaviour,
      default_modules: [:pool_supervisor, :monitor],
      worker_state_entity: nil,
      verbose: false
  @cluster :default_cluster


  #=======================================================
  # Cluster Operations and Calls
  #=======================================================

  #--------------------------
  # health_report/1
  #--------------------------
  def health_report(context) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context)
    c && c.health_report
  end

  #--------------------------
  # status/1
  #--------------------------
  def status(context) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context)
    c && c.status
  end

  #--------------------------
  # state/1
  #--------------------------
  def state(context) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context)
    c && c.state
  end

  #--------------------------
  # pending_state/1
  #--------------------------
  def pending_state(context) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context)
    c && c.pending_state
  end


  #--------------------------
  # status_details/2
  #--------------------------
  def status_details(context, options) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context)
    c && c.status_details
  end

  #--------------------------
  # block_for_state/3
  #--------------------------
  def block_for_state(desired_state, context, timeout \\ :infinity)
  def block_for_state(desired_state, context, timeout)  when is_atom(desired_state), do: block_for_state([desired_state], context, timeout)
  def block_for_state(desired_states, context, timeout) when is_list(desired_states) do
    wait_for_condition(
      fn ->
        s = state(context)
        Enum.member?(desired_states, s) && {:ok, s}
      end, timeout)
  end

  #--------------------------
  # block_for_status/3
  #--------------------------
  def block_for_status(desired_status, context, timeout \\ :infinity)
  def block_for_status(desired_status, context, timeout)  when is_atom(desired_status), do: block_for_status([desired_status], context, timeout)
  def block_for_status(desired_statuses, context, timeout) when is_list(desired_statuses) do
    wait_for_condition(
      fn ->
        s = status(context)
        Enum.member?(desired_statuses, s) && {:ok, s}
      end, timeout)
  end

  #--------------------------
  # manager_tenancy()
  #--------------------------
  def cluster_manager_tenancy() do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity.entity!(@cluster) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context)
    c && c.node
  end

  #--------------------------
  # lock_cluster/2
  #--------------------------
  def lock_cluster(instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c, {:lock_cluster, instructions}, context)


  #--------------------------
  # release_cluster/2
  #--------------------------
  def release_cluster(instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c,  {:release_cluster, instructions}, context)


  #--------------------------
  # bring_cluster_online/2
  #--------------------------
  def bring_cluster_online(instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c,  {:bring_cluster_online, instructions}, context)

  #--------------------------
  # take_cluster_offline/2
  #--------------------------
  def take_cluster_offline(instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c,  {:bring_cluster_online, instructions}, context)

  #--------------------------
  # rebalance_cluster/2
  #--------------------------
  def rebalance_cluster(instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c,  {:rebalance_cluster, instructions}, context)

  #--------------------------
  # log_telemetry/2
  #--------------------------
  def log_telemetry(telemetry, context) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context)
    c && c.telemetry_handler && c.telemetry_handler.log_telemetry({{:cluster, @cluster}, telemetry}, c)
  end

  #--------------------------
  # log_event/4
  #--------------------------
  def log_event(level, event, detail, context) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context)
    subject = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity.ref(@cluster)
    c && c.event_handler && c.event_handler.log_event(subject, level, event, detail, context)
  end

  #=======================================================
  # Service Operations and Calls
  #=======================================================

  #--------------------------
  # service_health_report/3
  #--------------------------
  def service_health_report(service, context, options \\ %{}) do
    service.service_manager().health_report(service, context, options)
  end

  #--------------------------
  # service_status/3
  #--------------------------
  def service_status(service, context, options \\ %{}) do
    service.service_manager().status(service, context, options)
  end

  #--------------------------
  # service_state/3
  #--------------------------
  def service_state(service, context, options \\ %{}) do
    service.service_manager().state(service, context, options)
  end

  #--------------------------
  # pending_state/3
  #--------------------------
  def service_pending_state(service, context, options \\ %{}) do
    service.service_manager().pending_state(service, context, options)
  end


  #--------------------------
  # service_definitions/2
  #--------------------------
  def service_definitions(context, options \\ %{}) do
    c = cond do
      options[:cache] == false -> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context)
      true -> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context, options)
    end
    c && c.service_definitions
  end

  #--------------------------
  # service_definition/3
  #--------------------------
  def service_definition(service, context, options \\ %{}) do
    c = cond do
      options[:cache] == false -> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context)
      true -> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context, options)
    end
    c && c.service_definitions[service]
  end

  #--------------------------
  # services_status_details/2
  #--------------------------
  def services_status_details(context, options \\ %{}) do
    c = cond do
      options[:cache] == false -> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context)
      true -> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.get!(@cluster, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.cached(@cluster, context, options)
    end
    c && c.service_statuses
  end

  #--------------------------
  # service_status_details/3
  #--------------------------
  def service_status_details(service, context, options) do
    service.service_manager().status_details(service, context, options)
  end

  #--------------------------
  # block_for_service_state/5
  #--------------------------
  def block_for_service_state(service, desired_state, context, options, timeout \\ :infinity)
  def block_for_service_state(service, desired_state, context, options, timeout)  when is_atom(desired_state), do: block_for_service_state(service, [desired_state], context, options, timeout)
  def block_for_service_state(service, desired_states, context, options, timeout) when is_list(desired_states) do
    wait_for_condition(
      fn ->
        s = service_state(service, context, options)
        Enum.member?(desired_states, s) && {:ok, s}
      end, timeout)
  end

  #--------------------------
  # block_for_service_status/5
  #--------------------------
  def block_for_service_status(service, desired_status, context, options, timeout \\ :infinity)
  def block_for_service_status(service, desired_status, context, options, timeout)  when is_atom(desired_status), do: block_for_service_status(service, [desired_status], context, options, timeout)
  def block_for_service_status(service, desired_statuses, context, options, timeout) when is_list(desired_statuses) do
    wait_for_condition(
      fn ->
        s = service_status(service, context, options)
        Enum.member?(desired_statuses, s) && {:ok, s}
      end, timeout)
  end

  #--------------------------
  # lock_service/3
  #--------------------------
  def lock_service(service, instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c,  {:lock_service, service, instructions}, context)

  #--------------------------
  # release_service/3
  #--------------------------
  def release_service(service, instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c,  {:release_service, service, instructions}, context)

  #--------------------------
  # register_service/4
  #--------------------------
  def register_service(service, service_definition, instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c,  {:register_service, service, service_definition, instructions}, context)

  #--------------------------
  # bring_service_online/3
  #--------------------------
  def bring_service_online(service, instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c,  {:bring_service_online, service, instructions}, context)

  #--------------------------
  # take_service_offline/3
  #--------------------------
  def take_service_offline(service, instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c,  {:take_service_offline, service, instructions}, context)

  #--------------------------
  # rebalance_service/3
  #--------------------------
  def rebalance_service(service, instructions, context), do: (c = cluster_manager_tenancy()) && __MODULE__.Server.Router.remote_system_call(c,  {:rebalance_service, service, instructions}, context)

  #======================================================
  # Server Module
  #======================================================
  defmodule Server do
    @vsn 1.0
    alias Noizu.SimplePool.V2.Server.State

    use Noizu.SimplePool.V2.ServerBehaviour,
        worker_state_entity: nil
    require Logger

    #-----------------------------
    # initial_state/2
    #-----------------------------
    def initial_state(configuration, context) do
      # @TODO exception handling
      cluster_state = Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity.entity!(@cluster)
                      |> IO.inspect(pretty: true, limit: :infinity)
                      |> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity.reset(context)
                      |> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.update!(context)

      {:ok, h_ref} = :timer.send_after(5_000, self(), {:passive, {:i, {:cluster_heart_beat}, context}})

      %State{
        pool: pool(),
        entity: cluster_state,
        status_details: :initialized,
        extended: %{},
        environment_details: %{heart_beat: h_ref},
        options: option_settings()
      }
    end

    #-----------------------------
    # cluster_heart_beat/2
    #-----------------------------
    def info__cluster_heart_beat(state, context) do
      # @todo update reports, send alert messages, etc.
      Logger.info("Cluster Heart Beat")
      {:ok, h_ref} = :timer.send_after(5_000, self(), {:passive, {:i, {:cluster_heart_beat}, context}})
      {:noreply, state}
    end

    #-----------------------------
    # call handlers
    #-----------------------------
    def call__lock_cluster(state,  instructions, context), do: {:reply, :feature_pending, state}
    def call__release_cluster(state,  instructions, context), do: {:reply, :feature_pending, state}
    def call__bring_cluster_online(state,  instructions, context), do: {:reply, :feature_pending, state}
    def call__take_cluster_offline(state,  instructions, context), do: {:reply, :feature_pending, state}
    def call__rebalance_cluster(state,  instructions, context), do: {:reply, :feature_pending, state}
    def call__lock_service(state,  service, instructions, context), do: {:reply, :feature_pending, state}
    def call__release_service(state,  service, instructions, context), do: {:reply, :feature_pending, state}
    def call__register_service(state,  service, service_definition, instructions, context), do: {:reply, :feature_pending, state}
    def call__bring_service_online(state,  service, instructions, context) do
      # Stub Logic
      state = state
              |> put_in([Access.key(:entity), Access.key(:status)], :green)
              |> put_in([Access.key(:entity), Access.key(:state)], :online)
      # Final logic pending - ping services and write records to inform services/nodes they need to report in. Once all have reported and are online change status and state. after timeout if missing coverage use :degraded status, :online state.

      Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.update!(state.entity, Noizu.ElixirCore.CallingContext.system(context))

      {:reply, :pending, state}
    end
    def call__take_service_offline(state,  service, instructions, context), do: {:reply, :feature_pending, state}
    def call__rebalance_service(state,  service, instructions, context)do
      # Stub Logic
      state = state
              |> put_in([Access.key(:entity), Access.key(:status)], :offline)
              |> put_in([Access.key(:entity), Access.key(:state)], :offline)
      # pending, coordinate with cluster manager and service definitions to determine what service instances need to be launched
      Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.update!(state.entity, Noizu.ElixirCore.CallingContext.system(context))

      {:reply, :pending, state}
    end

    #------------------------------------------------------------------------
    # call router
    #------------------------------------------------------------------------
    def call_router_user({:spawn, envelope}, from, state), do: call_router_user(envelope, from, state)
    def call_router_user({:passive, envelope}, from, state), do: call_router_user(envelope, from, state)
    def call_router_user(envelope, _from, state) do
      case envelope do
        {:m, {:lock_cluster,  instructions}, context} -> call__lock_cluster(state,  instructions, context)
        {:m, {:release_cluster,  instructions}, context} -> call__release_cluster(state,  instructions, context)
        {:m, {:bring_cluster_online,  instructions}, context} -> call__bring_cluster_online(state,  instructions, context)
        {:m, {:take_cluster_offline,  instructions}, context} -> call__take_cluster_offline(state,  instructions, context)
        {:m, {:rebalance_cluster,  instructions}, context} -> call__rebalance_cluster(state,  instructions, context)
        {:m, {:lock_service,  service, instructions}, context} -> call__lock_service(state,  service, instructions, context)
        {:m, {:release_service,  service, instructions}, context} -> call__release_service(state,  service, instructions, context)
        {:m, {:register_service,  service, service_definition, instructions}, context} -> call__register_service(state,  service, service_definition, instructions, context)
        {:m, {:bring_service_online,  service, instructions}, context} -> call__bring_service_online(state,  service, instructions, context)
        {:m, {:take_service_offline,  service, instructions}, context} -> call__take_service_offline(state,  service, instructions, context)
        {:m, {:rebalance_service,  service, instructions}, context} -> call__rebalance_service(state,  service, instructions, context)
        _ -> nil
      end
    end

    def infp_router_user({:spawn, envelope}, state), do: info_router_user(envelope, state)
    def info_router_user({:passive, envelope}, state), do: info_router_user(envelope, state)
    def info_router_user(envelope, state) do
      case envelope do
        {:i, {:cluster_heart_beat}, context} -> info__cluster_heart_beat(state,  context)
        _ -> nil
      end
    end

  end # end defmodule Server
end
