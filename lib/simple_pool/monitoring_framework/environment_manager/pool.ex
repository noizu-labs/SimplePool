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

    # @TODO consider re-registration on terminate.

    use Noizu.SimplePool.ServerBehaviour,
        worker_state_entity: Noizu.MonitoringFramework.EnvironmentWorkerEntity,
        override: [:init]


    def handle_cast({:i, {:update_hints, options}, context}, state) do
      internal_update_hints(state.entity.effective, context, options)
      {:noreply, state}
    end

    def handle_call({:i, {:node_health_check!, options}, context}, _from, state) do
      state = update_effective(state, context, options)
      {:reply, {:ack, state.entity.effective}, state}
    end

    def handle_call({:i, {:lock, components, options}, context}, _from, state) do
      c = MapSet.to_list(components)
      state = Enum.reduce(c, state, fn(component, acc) ->
        if state.effective.services[component] do
          state = state
                  |> put_in([Access.key(:entity), :effective, Access.key(:services), component, Access.key(:directive)], :maintenance)
                  |> put_in([Access.key(:entity), :effective, Access.key(:services), component, Access.key(:status)], :locked)
        else
          acc
        end
      end)

      %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{
        identifier: state.entity.effective.identifier,
        status: state.entity.effective.status,
        directive: state.entity.effective.directive,
        health_index: state.entity.effective.health_index,
        entity: state.entity.effective
      } |> Noizu.SimplePool.Database.MonitoringFramework.NodeTable.write!()

      case options[:update_hints] do
        nil -> internal_update_hints(state.entity.effective, context, options)
        true -> internal_update_hints(state.entity.effective, context, options)
        false -> :skip
      end

      {:reply, :ack, state}
    end



    def handle_call({:i, {:release, components, options}, context}, _from, state) do
      c = MapSet.to_list(components)
      state = Enum.reduce(c, state, fn(component, acc) ->
        if state.effective.services[component] do
          state = state
                  |> put_in([Access.key(:entity), :effective, Access.key(:services), component, Access.key(:directive)], :active)
                  |> put_in([Access.key(:entity), :effective, Access.key(:services), component, Access.key(:status)], :online)
        else
          acc
        end
      end)

      %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{
        identifier: state.entity.effective.identifier,
        status: state.entity.effective.status,
        directive: state.entity.effective.directive,
        health_index: state.entity.effective.health_index,
        entity: state.entity.effective
      } |> Noizu.SimplePool.Database.MonitoringFramework.NodeTable.write!()

      case options[:update_hints] do
        nil -> internal_update_hints(state.entity.effective, context, options)
        true -> internal_update_hints(state.entity.effective, context, options)
        false -> :skip
      end

      {:reply, :ack, state}
    end


    #----------------------------------------------------------------------------
    # START| Noizu.SimplePool.MonitoringFramework.MonitorBehaviour
    #----------------------------------------------------------------------------
    @behaviour Noizu.SimplePool.MonitoringFramework.MonitorBehaviour

    def supports_service?(server, component, _context, options \\ %{}) do
      effective = case Noizu.SimplePool.Database.MonitoringFramework.NodeTable.read!(server) do
        nil -> :nack
        v ->
          if v.entity.services[component] do
            case v.entity.services[component].status do
              :online -> :ack
              :degraded -> :ack
              :critical -> :ack
              :offline ->
                if options[:initializing] do
                  :ack
                else
                  IO.puts "supports_service? nack 2 :offline - #{inspect {server, component, options}}"
                  :nack
                end


              s ->
                IO.puts "supports_service? nack 3 #{inspect s} - #{inspect {server, component, options}}"
                :nack
            end
          else
            IO.puts "supports_service? nack 4"
            :nack
          end
      end
    end

    def rebalance(input, output, components, context, options \\ %{}) do

      server_list = MapSet.to_list(input)
      component_list = MapSet.to_list(components)

      all_tasks = Enum.reduce(component_list, [], fn(component, acc) ->
        cs = (Module.concat([component, "Server"]))

        tasks = Enum.reduce(server_list, [], fn(server, acc2) ->
          acc2 ++ [Task.async(fn ->  {server, cs.workers!(server, context, options)} end)]
        end)

        workers = Enum.reduce(tasks, %{}, fn(task, acc3) ->
          {s, {:ack, workers}} = Task.await(task)
          Map.put(acc3, s, workers)
        end)

        total_workers = Enum.reduce(workers, 0, fn({s,v}, acc4) -> acc4 + length(v) end)
        oc = MapSet.size(output)
        wps = div(total_workers, oc)

        p_one = Enum.reduce(workers, {%{}, []}, fn({k,v}, {om, ol}) ->
          if MapSet.member?(output, k) do
            {a,b} = Enum.split(v, wps)
            {Map.put(om, k, a), ol ++ b}
          else
            {om, ol ++ v}
          end
        end)

        output_list = MapSet.to_list(output)
        {p_two, r_p} = Enum.reduce(output_list, p_one, fn(s, {om, ol}) ->
          if om[s] do
            oml = length(om[s])
            {a, b} = Enum.split(ol, wps - oml)
            {put_in(om, [s], om[s] ++ a), b}
          else
            {a, b} = Enum.split(ol, wps)
            {put_in(om, [s], a), b}
          end
        end)

        remap_tasks = Enum.reduce(p_two, [], fn({s,p}, acc5) ->
          Enum.reduce(p, acc5, fn(process, acc6) ->
            {source, ref} = process
            acc6 ++ [Task.async(fn -> cs.worker_migrate!(ref, s, context, options) end)]
          end)
        end)
        acc ++ remap_tasks
      end)


      for t <- all_tasks do
        Task.await(t)
      end

      :ack
    end

    def lock(servers, components, context, options \\ %{}) do
      options_b = put_in(options, [:update_hints], false)
      locks = for server <- servers do
        Task.async(fn -> remote_call(server, {:lock, components, options}, context, options_b) end)
      end

      for lock <- locks do
        Task.await(lock)
      end

      # Update Hints
      case options[:update_hints] do
        nil -> internal_update_hints(components, context, options)
        true -> internal_update_hints(components, context, options)
        false -> :skip
      end

      :ack
    end

    def release(servers, components, context, options \\ %{}) do
      options_b = put_in(options, [:update_hints], false)
      locks = for server <- servers do
        Task.async(fn -> remote_call(server, {:release, components, options}, context, options_b) end)
      end

      for lock <- locks do
        Task.await(lock)
      end

      # Update Hints
      case options[:update_hints] do
        nil -> internal_update_hints(components, context, options)
        true -> internal_update_hints(components, context, options)
        false -> :skip
      end

      :ack
    end

    def select_host(_ref, component, _context, _options \\ %{}) do
      case Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable.read!(component) do
        nil -> {:nack, :hint_required}
        v ->
          if v.status === %{} do
            {:nack, :none_available}
          else
            # TODO handle no hints, illegal format, etc.
            {{host, _service}, v} = Enum.random(v.hint)
            {:ack, host}
          end
      end
    end

    def record_server_event(server, event, details, context, options \\ %{}) do
      time = options[:time] || DateTime.utc_now()
      entity = %Noizu.SimplePool.MonitoringFramework.LifeCycleEvent{
        identifier: event,
        time_stamp: time,
        details: details
      }
      %Noizu.SimplePool.Database.MonitoringFramework.Node.EventTable{identifier: server, event: event, time_stamp: DateTime.to_unix(time), entity: entity}
      |> Noizu.SimplePool.Database.MonitoringFramework.Node.EventTable.write!()
      :ack
    end

    def record_service_event(server, service, event, details, context, options \\ %{}) do
      time = options[:time] || DateTime.utc_now()
      entity = %Noizu.SimplePool.MonitoringFramework.LifeCycleEvent{
        identifier: event,
        time_stamp: time,
        details: details
      }
      %Noizu.SimplePool.Database.MonitoringFramework.Service.EventTable{identifier: {server, service}, event: event, time_stamp: DateTime.to_unix(time), entity: entity}
      |> Noizu.SimplePool.Database.MonitoringFramework.Service.EventTable.write!()
      :ack
    end

    #----------------------------------------------------------------------------
    # END| Noizu.SimplePool.MonitoringFramework.MonitorBehaviour
    #----------------------------------------------------------------------------

    def handle_info({:DOWN, ref, :process, process, msg} = event, state) do
      IO.puts "LINK MONITOR: #{inspect event, pretty: true}"
      monitors = Enum.reduce(state.entity.monitors, %{}, fn({k,v}, acc) ->
        if ref == v do
          Map.put(acc, k, nil)
        else
          Map.put(acc, k, v)
        end
      end)
      state = put_in(state, [Access.key(:entity), :monitors], monitors)
      {:noreply, state}
    end

    alias Noizu.SimplePool.Server.State

    def init([sup, definition, context] = args) do
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

      IO.puts "INIT #{inspect definition}"
      state = %State{
        pool: Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor,
        server: Noizu.MonitoringFramework.EnvironmentPool.Server,
        status_details: :pending,
        extended: %{monitors: %{}},
        options: option_settings(),
        entity: %{server: node(), definition: definition, initial: definition.server_options.initial, effective: %{}, default: nil, status: :offline, monitors: %{}}
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

    def update_hints!(context, options \\ %{}) do
      internal_cast({:update_hints, options}, context)
    end

    def internal_update_hints(effective, context, options \\ %{}) do
      remote_cast(effective.master_node, {:hint_update, effective, options}, context)
    end

    #---------------------------------------------------------------------------
    # Handlers
    #---------------------------------------------------------------------------
    def perform_join(state, server, {pid, ref}, initial, context, options) do

      effective = case Noizu.SimplePool.Database.MonitoringFramework.NodeTable.read!(server) do
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

      monitor_ref = Process.monitor(pid)
      put_in(state, [Access.key(:extended), :monitors, server], monitor_ref)
      {:reply, effective, state}
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
      state
    end

    def node_health_check!(context, options) do
      internal_call({:node_health_check!, options[:node_health_check!] || %{}}, context, options)
    end

    def perform_hint_update(state, effective, context, options) do
      # call each service node to get current health checks.
      # 1. Grab nodes
      servers = Amnesia.Fragment.async(fn ->
        Noizu.SimplePool.Database.MonitoringFramework.NodeTable.where(1 == 1)
        |> Amnesia.Selection.values
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
        candidates = Enum.reduce(servers, [], fn ({server_id, server}, acc2) ->
          s = server.services[service]
          cond do
            MapSet.member?(valid_status, server.status) && s && MapSet.member?(valid_status, s.status) ->
              acc2 ++ [%{identifier: s.identifier, server_status: server.status, server_index: server.health_index, service_status: s.status, service_index: s.health_index, index: server.health_index + s.health_index}]
            true ->
              acc2
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
      initial = initial || state.entity.initial
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
      else
        master
      end

      if master do
        if master == node() do
          effective = case Noizu.SimplePool.Database.MonitoringFramework.NodeTable.read!(node()) do
            nil -> initial
            v = %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{} -> v.entity
          end
          effective = put_in(effective, [Access.key(:master_node)], master)
          %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{
            identifier: effective.identifier,
            status: effective.status,
            directive: effective.directive,
            health_index: effective.health_index,
            entity: effective
          } |> Noizu.SimplePool.Database.MonitoringFramework.NodeTable.write!()

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
      monitors = Enum.reduce(state.entity.effective.services, %{}, fn({k,v}, acc) ->
        {:ok, sup_pid} = v.definition.supervisor.start_link(context, v.definition)
        m = Process.monitor(sup_pid)
        Map.put(acc, k, m)
      end)

      options_b = put_in(options, [:initializing], true)
      tasks = Enum.reduce(state.entity.effective.services, [], fn({k,v}, acc) ->
        acc ++ [Task.async( fn ->
          h = v.definition.pool.service_health_check!(options[:health_check_options] || %{}, context, options_b)
          {k,h} end)]
      end)

      state = Enum.reduce(tasks, state, fn(t, acc) ->
        {k, v} = Task.await(t)
        Process.sleep(1_000)

        case v do
          %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{} ->
            acc
            |> put_in([Access.key(:entity), :effective, Access.key(:services), k], v)
          e ->
            Logger.error("#{node()} - Service Startup Error #{inspect k} - #{inspect e}")
            acc
            |> put_in([Access.key(:entity), :effective, Access.key(:services), k, Access.key(:status)], :error)
        end

      end)

      state = state
              |> put_in([Access.key(:entity), :effective, Access.key(:status)], :online)
              |> put_in([Access.key(:entity), :status], :online)
              |> put_in([Access.key(:entity), :monitors], monitors)

      %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{
        identifier: state.entity.effective.identifier,
        status: state.entity.effective.status,
        directive: state.entity.effective.directive,
        health_index: state.entity.effective.health_index,
        entity: state.entity.effective
      } |> Noizu.SimplePool.Database.MonitoringFramework.NodeTable.write!()

      internal_update_hints(state.entity.effective, context, options)
      {:noreply, state}
    end

  end # end defmodule GoldenRatio.Components.Gateway.Server
end # end defmodule GoldenRatio.Components.Gateway
