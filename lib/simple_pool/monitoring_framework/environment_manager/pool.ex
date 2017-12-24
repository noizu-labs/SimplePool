#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.MonitoringFramework.EnvironmentPool do
  #alias Noizu.Scaffolding.CallingContext
  use Noizu.SimplePool.Behaviour,
      default_modules: [:pool_supervisor, :worker_supervisor],
      worker_state_entity: Noizu.MonitoringFramework.EnvironmentWorkerEntity,
      verbose: false

  use Amnesia
  use Noizu.SimplePool.Database.MonitoringFramework.NodeTable

  defmodule Worker do
    @vsn 1.0
    use Noizu.SimplePool.WorkerBehaviour,
        worker_state_entity: Noizu.MonitoringFramework.EnvironmentWorkerEntity,
        verbose: false
    require Logger
  end # end worker

  #=============================================================================
  # @Server
  #=============================================================================
  defmodule Server do
    @vsn 1.0
    use Noizu.SimplePool.ServerBehaviour,
        worker_state_entity: Noizu.MonitoringFramework.EnvironmentWorkerEntity,
        override: [:init]

    alias Noizu.SimplePool.Server.State

    def init([sup, context, definition] = args) do
      if verbose() do
        Logger.info(fn -> {base().banner("INIT #{__MODULE__} (#{inspect Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor}@#{inspect self()})"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
      end

      # TODO load real effective
      effective = %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{
        identifier: {node(), base()},
        time_stamp: DateTime.utc_now(),
        status: :offline,
        directive: :init,
        definition: definition,
      }


      state = %State{
        pool: Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor,
        server: Noizu.MonitoringFramework.EnvironmentPool.Server,
        status_details: :pending,
        extended: %{monitors: %{}},
        options: option_settings(),
        entity: %{server: node(), definition: definition, effective: effective, default: nil, status: :offline}
      }
      {:ok, state}
    end

    #---------------------------------------------------------------------------
    # Convenience Methods
    #---------------------------------------------------------------------------

    def register(initial, context, options \\ %{}) do
      GenServer.call(__MODULE__, {:m, {:register, initial, options}, context}, 30_000)
    end

    def start_services(context, options \\ %{}) do
      GenServer.cast(__MODULE__, {:m, {:start_services, options}, context})
    end

    def update_hints(effective, context, options \\ %{}) do
      remote_cast(effective.master_node, {:hint_update, effective, options}, context)
    end

    #---------------------------------------------------------------------------
    # Handlers
    #---------------------------------------------------------------------------
    def perform_join(state, server, from, initial, context, options) do

      effective = case Noizu.SimplePool.Database.MonitoringFramework.NodeTable.read!(node()) do
        nil -> initial
        v -> v.entity
      end
      effective = put_in(effective, [Access.key(:master_node)], node())

      s = %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{
        identifier: effective.identifier,
        status: effective.status,
        directive: effective.directive,
        health_index: effective.health_index,
        entity: effective
      } |> Noizu.SimplePool.Database.MonitoringFramework.NodeTable.write!()

      monitor_ref = Process.monitor(from)
      put_in(state, [Access.key(:extended), :monitors, server], monitor_ref)
      {:reply, effective, state}
    end

    def handle_call({:i, {:node_health_check!, options}, context}, _from, state) do
      state = update_effective(state, context, options)
      {:reply, {:ack, state.effective}, state}
    end


    def update_effective(state, context, options) do
      tasks = Enum.reduce(state.entity.effective.services, [], fn({k,v}, acc) ->
        acc ++ [Task.async( fn ->
          h = v.definition.pool.service_health_check!(options[:health_check_options] || %{}, context, options)
          {k,h} end)]
      end)

      effective = Enum.reduce(tasks, state.entity.effective, fn(t, acc) ->
        {k, v} = Task.await(t)
        put_in(acc, [Access.key(:services), k], v)
      end)

      state = put_in(state, [Access.key(:entity), :effective], effective)
    end

    def node_health_check!(context, options) do
      internal_call({:node_health_check!, options}, context)
    end

    def perform_hint_update(state, effective, context, options) do
      # call each service node to get current health checks.

      # 1. Grab nodes
      servers = Amnesia.Fragment.async(fn ->
        Noizu.SimplePool.Database.MonitoringFramework.NodeTable.where(1 == 1)
        |> Amnesia.selection.values
      end)

      state = update_effective(state, context, options)

      # 2. Grab Server Status
      tasks = Enum.reduce(servers, [], fn(x, acc) ->
        if (x.identifier != node()) do
          task = Task.async( fn ->
            {x.identifier, :rpc.call(x.identifier, __MODULE__, :node_health_check!, [context, options])}
          end)
          acc ++ [task]
        else
          task = Task.async( fn -> {x.identifier, {:ack, state.entity.effective}} end)
          acc ++ [task]
        end
      end)

      servers = Enum.reduce(tasks, %{}, fn (task, acc) ->
         {k, {:ack, v}} = Task.await(task)
         Map.put(acc, k, v)
      end)

      # 3. Calculate Hints
      valid_status = MapSet.new([:online, :degraded, :critical])
      valid_status_weight = %{online: 1, degraded: 2, critical: 3}

      update = Map.keys(effective.services)
      Enum.reduce(update, true, fn(service, acc) ->
        candidates = Enum.reduce(servers, [], fn (server, acc2) ->
        s = server.services[service]
          cond do
            MapSet.member?(valid_status, server.status) && s && MapSet.member?(valid_status, s.status) ->
              acc2 ++ [%{identifier: s.identifier, server_status: server.status, server_index: server.health_index, service_status: s.status, service_index: s.health_index, index: server.health_index + s.health_index}]
            true -> acc2
          end
        end)


        candidates = Enum.sort(candidates, fn(a,b) ->
          cond do
            a.server_status == b.server_status ->
              cond do
                b.service_status == b.service_status -> a.index < b.index
                true -> valid_status_weight[a.service_status] < valid_status_weight[b.service_status]
              end
            true -> valid_status_weight[a.server_status] < valid_status_weight[b.server_status]
          end
        end)


        # 1. add a minimum of 3 nodes, plus any good nodes
        IO.puts "length 1 - #{inspect candidates}











        "
        candidate_pool_size = length(candidates)
        min_bar = candidate_pool_size / 3
        hint = Enum.reduce(candidates, [], fn(x,acc3) ->
          cond do
            length(acc3) == 0 -> acc3 ++ [x]
            length(acc3) <= min_bar -> acc3 ++ [x]
            x.server_status == :online && x.service_status == :online ->  acc3 ++ [x]
            true -> acc3
          end
        end)

        hint_status = Enum.reduce(hint, {:online, :online}, fn(x, {wserver, wservice}) ->
          cond do
            valid_status_weight[wserver] < valid_status_weight[x.server_status] -> {x.server_status, x.service_status}
            valid_status_weight[wserver] == valid_status_weight[x.server_status] && valid_status_weight[wservice] < valid_status_weight[x.service_status] -> {x.server_status, x.service_status}
            true -> {wserver, wservice}
          end
        end)

        hints = Enum.reduce(hint, %{}, fn(x,acc) -> Map.put(acc, x.identifier, x.index) end)

        %Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable{identifier: service, hint: hints, time_stamp: DateTime.utc_now, status: hint_status}
          |> Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable.write!()
        :ok
      end)

      # 3. Update Service Hints.
      {:noreply, state}
    end

    def handle_cast({:i, {:hint_update, effective, options}, context}, state) do
      perform_hint_update(state, effective, context, options)
    end

    def handle_call({:i, {:join, server, initial, options}, context}, from, state) do
      perform_join(state, server, from, initial, context, options)
    end

    def handle_call({:m, {:register, initial, options}, context}, _from, state) do
      master = case Noizu.SimplePool.Database.MonitoringFramework.SettingTable.read!(:environment_master) do
        nil -> nil
        [] -> nil
        [%Noizu.SimplePool.Database.MonitoringFramework.SettingTable{value: v}] -> v
      end

      master = if master == nil do
        if initial.master_node == :self || initial.master_node == node() do
          %Noizu.SimplePool.Database.MonitoringFramework.SettingTable{setting: :environment_master, value: node()}
            |>  Noizu.SimplePool.Database.MonitoringFramework.SettingTable.write!()
          node()
        else
          nil
        end
      end

      if master do
        if master == node() do
          effective = Noizu.SimplePool.Database.MonitoringFramework.NodeTable.read!(node()) || initial
          effective = put_in(effective, [Access.key(:master_node)], master)
          state = state
                  |> put_in([Access.key(:entity), :effective], effective)
                  |> put_in([Access.key(:entity), :default], initial)
                  |> put_in([Access.key(:entity), :status], :registered)
          {:reply, {:ack, state.entity.effective}, state}
        else
          effective = remote_call(master, {:join, node(), initial, options}, context)
          state = state
                  |> put_in([Access.key(:entity), :effective], effective)
                  |> put_in([Access.key(:entity), :default], initial)
                  |> put_in([Access.key(:entity), :status], :registered)
          {:reply, {:ack, state.entity.effective}, state}
        end
      else
        {:reply, {:error, :master_node_required}, state}
      end
    end

    def handle_cast({:m, {:start_services, options}, context}, state) do
      Enum.reduce(state.entity.effective.services, :ok, fn({k,v}, acc) ->
        v.definition.supervisor.start_link(context, v.definition)
      end)

      tasks = Enum.reduce(state.entity.effective.services, [], fn({k,v}, acc) ->
        acc ++ [Task.async( fn ->
          h = v.definition.pool.service_health_check!(options[:health_check_options] || %{}, context, options)
          {k,h} end)]
      end)

      # @TODO register process watcher for services.

      effective = Enum.reduce(tasks, state.entity.effective, fn(t, acc) ->
        {k, v} = Task.await(t)
        put_in(acc, [Access.key(:services), k], v)
      end)

      # @TODO update hints
      update_hints(effective, context, options)

      state = state
              |> put_in([Access.key(:entity), :effective], effective)
              |> put_in([Access.key(:entity), :status], :online)

      {:noreply, state}
    end

  end # end defmodule GoldenRatio.Components.Gateway.Server
end # end defmodule GoldenRatio.Components.Gateway
