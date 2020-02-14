#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule Noizu.SimplePool.V2.ClusterManagementFramework.Cluster.ServiceManager do
  @moduledoc """
     The service monitor is responsible for monitoring health of a service spanning one or more nodes and coordinating rebalances, shutdowns and other activities.
  """
  use Noizu.SimplePool.V2.PoolBehaviour,
      default_modules: [:pool_supervisor, :monitor],
      worker_state_entity: Noizu.SimplePool.V2.ClusterManagementFramework.Cluster.ServiceManager.WorkerEntity,
      verbose: false

  #=======================================================
  # Service Operations and Calls
  #=======================================================

  #--------------------------
  # service_health_report/3
  #--------------------------
  def service_health_report(service, context, options \\ %{}) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.get!(service, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.cached(service, context)
    c && c.health_report
  end

  #--------------------------
  # service_status/3
  #--------------------------
  def service_status(service, context, options \\ %{}) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.get!(service, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.cached(service, context)
    c && c.status
  end

  #--------------------------
  # service_state/3
  #--------------------------
  def service_state(service, context, options \\ %{}) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.get!(service, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.cached(service, context)
    c && c.state
  end

  #--------------------------
  # pending_state/3
  #--------------------------
  def service_pending_state(service, context, options \\ %{}) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.get!(service, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.cached(service, context)
    c && c.pending_state
  end

  #--------------------------
  # service_definition/3
  #--------------------------
  defdelegate service_definition(service, context, options \\ %{}), to: Noizu.SimplePool.V2.ClusterManagementFramework.ClusterManager

  #--------------------------
  # service_status_details/3
  #--------------------------
  def service_status_details(service, context, options) do
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.get!(service, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.cached(service, context)
    c && c.status_details
  end

  #--------------------------
  # block_for_service_state/5
  #--------------------------
  defdelegate block_for_service_state(service, desired_state, context, options, timeout \\ :infinity), to: Noizu.SimplePool.V2.ClusterManagementFramework.ClusterManager

  #--------------------------
  # block_for_service_status/5
  #--------------------------
  defdelegate block_for_service_status(service, desired_status, context, options, timeout \\ :infinity), to: Noizu.SimplePool.V2.ClusterManagementFramework.ClusterManager

  #--------------------------
  # lock_service/3
  #--------------------------
  def lock_service(service, instructions, context), do: __MODULE__.Server.Router.s_call!(service, {:lock_service, service, instructions}, context)

  #--------------------------
  # release_service/3
  #--------------------------
  def release_service(service, instructions, context), do: __MODULE__.Server.Router.s_call!(service, {:release_service, service, instructions}, context)

  #--------------------------
  # register_service/4
  #--------------------------
  def register_service(service, service_definition, instructions, context), do: __MODULE__.Server.Router.s_call!(service, {:register_service, service, service_definition, instructions}, context)

  #--------------------------
  # bring_service_online/3
  #--------------------------
  def bring_service_online(service, instructions, context), do: __MODULE__.Server.Router.s_call!(service, {:bring_service_online, service, instructions}, context)

  #--------------------------
  # take_service_offline/3
  #--------------------------
  def take_service_offline(service, instructions, context), do: __MODULE__.Server.Router.s_call!(service, {:take_service_offline, service, instructions}, context)

  #--------------------------
  # rebalance_service/3
  #--------------------------
  def rebalance_service(service, instructions, context), do: __MODULE__.Server.Router.s_call!(service, {:rebalance_service, service, instructions}, context)



  #=======================================================
  # Service Instance Operations and Calls
  #=======================================================

  #--------------------------
  # service_instance_health_report/4
  #--------------------------
  def service_instance_health_report(service, instance, context, options \\ %{}) do
    service.node_manager().service_instance_health_report(instance, service, context, options)
  end

  #--------------------------
  # service_instance_status/4
  #--------------------------
  def service_instance_status(service, instance, context, options \\ %{}) do
    service.node_manager().service_instance_status(instance, service, context, options)
  end

  #--------------------------
  # service_instance_state/4
  #--------------------------
  def service_instance_state(service, instance, context, options \\ %{}) do
    service.node_manager().service_instance_state(instance, service, context, options)
  end

  #--------------------------
  # service_instance_pending_state/4
  #--------------------------
  def service_instance_pending_state(service, instance, context, options \\ %{}) do
    service.node_manager().service_instance_pending_state(instance, service, context, options)
  end

  #--------------------------
  # service_instance_definition/4
  #--------------------------
  def service_instance_definition(service, instance, context, options \\ %{}) do
    c = cond do
      options[:cache] == false -> Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.get!(service, context, options)
      true -> Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.get!(service, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.cached(service, context)
    end
    c && c.instance_definitions[instance]
  end

  #--------------------------
  # service_instance_status_details/4
  #--------------------------
  def service_instance_status_details(service, instance, context, options) do
    service.node_manager().service_instance_status_details(instance, service, context, options)
  end

  #--------------------------
  # block_for_service_instance_state/5
  #--------------------------
  def block_for_service_instance_state(service, instance, desired_state, context, options, timeout \\ :infinity)
  def block_for_service_instance_state(service, instance, desired_state, context, options, timeout)  when is_atom(desired_state), do: block_for_service_instance_state(service, instance, [desired_state], context, options, timeout)
  def block_for_service_instance_state(service, instance, desired_states, context, options, timeout) when is_list(desired_states) do
    wait_for_condition(
      fn ->
        s = service_instance_state(service, instance, context, options)
        Enum.member?(desired_states, s) && {:ok, s}
      end, timeout)
  end

  #--------------------------
  # block_for_service_status/5
  #--------------------------
  def block_for_service_instance_status(service, instance, desired_status, context, options, timeout \\ :infinity)
  def block_for_service_instance_status(service, instance, desired_status, context, options, timeout)  when is_atom(desired_status), do: block_for_service_instance_status(service, instance, [desired_status], context, options, timeout)
  def block_for_service_instance_status(service, instance, desired_statuses, context, options, timeout) when is_list(desired_statuses) do
    wait_for_condition(
      fn ->
        s = service_instance_status(service, instance, context, options)
        Enum.member?(desired_statuses, s) && {:ok, s}
      end, timeout)
  end

  #--------------------------
  # lock_service/4
  #--------------------------
  def lock_service_instance(service, instance, instructions, context), do: __MODULE__.Server.Router.s_call!(service, {:lock_service_instance, instance, instructions}, context)

  #--------------------------
  # release_service/4
  #--------------------------
  def release_service_instance(service, instance, instructions, context), do: __MODULE__.Server.Router.s_call!(service, {:release_service_instance, instance, instructions}, context)

  #--------------------------
  # bring_service_instance_online/4
  #--------------------------
  def bring_service_instance_online(service, instance, instructions, context), do: __MODULE__.Server.Router.s_call!(service, {:bring_service_instance_online, instance, instructions}, context)

  #--------------------------
  # take_service_instance_offline/4
  #--------------------------
  def take_service_instance_offline(service, instance, instructions, context), do: __MODULE__.Server.Router.s_call!(service, {:take_service_instance_offline, instance, instructions}, context)

  #--------------------------
  # select_host/4
  #--------------------------
  def select_host(service, ref, context, opts \\ %{}) do
    # Temporary rough logic, needs to check for service instance/node status, lock status, weight, health, etc.
    c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.get!(service, context) # c = Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateRepo.cached(service, context)
    instances = (c && c.instance_definitions || %{}) |> Enum.map(fn({k, _v}) -> k end)
    case Enum.take_random(instances, 1) do
      [n] -> {:ack, n}
      _ -> {:nack, :no_available_hosts}
    end
  end

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
    def initial_state([service, configuration], context) do
      # @TODO exception handling

      service_state = case Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity.entity!(service) do
        v =  %Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity{} ->
          v
          |> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity.reset(context, configuration)
          |> Noizu.SimplePool.V2.ClusterManagement.Cluster.StateRepo.update!(context)
        _ -> Noizu.SimplePool.V2.ClusterManagement.Cluster.Service.StateEntity.ref(service)
      end

      # @TODO setup heart beat for background processing.
      %State{
        pool: pool(),
        entity: service_state,
        status_details: :initialized,
        extended: %{},
        environment_details: %{},
        options: option_settings()
      }
    end

    #-----------------------------
    # cluster_heart_beat/2
    #-----------------------------
    def cluster_heart_beat(state, context) do
      # @todo update reports, send alert messages, etc.
      {:noreply, state}
    end

    #-----------------------------
    # call handlers
    #-----------------------------
    def call__lock_service(state,  service, instructions, context), do: {:reply, :feature_pending, state}
    def call__release_service(state,  service, instructions, context), do: {:reply, :feature_pending, state}
    def call__register_service(state,  service, service_definition, instructions, context), do: {:reply, :feature_pending, state}
    def call__bring_service_online(state,  service, instructions, context), do: {:reply, :feature_pending, state}
    def call__take_service_offline(state,  service, instructions, context), do: {:reply, :feature_pending, state}
    def call__rebalance_service(state,  service, instructions, context), do: {:reply, :feature_pending, state}
    def call__lock_service_instance(state,  instance, instructions, context), do: {:reply, :feature_pending, state}
    def call__release_service_instance(state,  instance, instructions, context), do: {:reply, :feature_pending, state}
    def call__bring_service_instance_online(state,  instance, instructions, context), do: {:reply, :feature_pending, state}
    def call__take_service_instance_offline(state,  instance, instructions, context), do: {:reply, :feature_pending, state}

    #-----------------------------
    # info handlers
    #-----------------------------
    def info__process_service_down_event(reference, process, reason, state) do
      cond do
        state.entity == nil ->
          Logger.error "[ServiceDown] Unknown State.Entity."
          {:noreply, state}
        rl = state.entity.meta[:monitor_lookup][reference] ->
          Logger.error "[ServiceDown] Service Has Stopped #{rl}."
          {:noreply, state}
        true ->
          Logger.error "[ServiceDown] Unknown DownLink #{inspect {reference, process, reason}}."
          {:noreply, state}
      end
    end


    #------------------------------------------------------------------------
    # call router
    #------------------------------------------------------------------------
    def call_router_user({:spawn, envelope}, from, state), do: call_router_user(envelope, from, state)
    def call_router_user({:passive, envelope}, from, state), do: call_router_user(envelope, from, state)
    def call_router_user(envelope, _from, state) do
      case envelope do
        {:s, {:lock_service,  service, instructions}, context} -> call__lock_service(state,  service, instructions, context)
        {:s, {:release_service,  service, instructions}, context} -> call__release_service(state,  service, instructions, context)
        {:s, {:register_service,  service, service_definition, instructions}, context} -> call__register_service(state,  service, service_definition, instructions, context)
        {:s, {:bring_service_online,  service, instructions}, context} -> call__bring_service_online(state,  service, instructions, context)
        {:s, {:take_service_offline,  service, instructions}, context} -> call__take_service_offline(state,  service, instructions, context)
        {:s, {:rebalance_service,  service, instructions}, context} -> call__rebalance_service(state,  service, instructions, context)
        {:s, {:lock_service_instance,  instance, instructions}, context} -> call__lock_service_instance(state,  instance, instructions, context)
        {:s, {:release_service_instance,  instance, instructions}, context} -> call__release_service_instance(state,  instance, instructions, context)
        {:s, {:bring_service_instance_online,  instance, instructions}, context} -> call__bring_service_instance_online(state,  instance, instructions, context)
        {:s, {:take_service_instance_offline,  instance, instructions}, context} -> call__take_service_instance_offline(state,  instance, instructions, context)
        _ -> nil
      end
    end

    #------------------------------------------------------------------------
    # info router
    #------------------------------------------------------------------------
    def info_router_user(envelope, state) do
      case envelope do
        {:DOWN, reference, :process, process, reason} -> info__process_service_down_event(reference, process, reason, state)
        _ -> nil
      end
    end



  end # end defmodule Server
end
