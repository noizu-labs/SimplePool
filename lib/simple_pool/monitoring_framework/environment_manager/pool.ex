#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
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
      internal_update_hints(state.environment_details.effective, context, options)
      {:noreply, state}
    end


    def handle_cast({:i, {:prep_hint_update, components, options}, context}, state) do
      remote_system_cast(state.environment_details.effective.master_node, {:hint_update, components, options}, context)
      {:noreply, state}
    end


    def handle_cast({:i, {:hint_update, components, options}, context}, state) do
      perform_hint_update(state, components, context, options)
    end

    def handle_cast({:m, {:start_services, options}, context}, state) do
      await_timeout = options[:wait] || 60_000
      monitors = Enum.reduce(state.environment_details.effective.services, %{}, fn({k,v}, acc) ->
        {:ok, sup_pid} = v.definition.supervisor.start_link(context, v.definition)
        m = Process.monitor(sup_pid)
        Map.put(acc, k, m)
      end)

      tasks = Enum.reduce(state.environment_details.effective.services, [], fn({k,v}, acc) ->
        acc ++ [Task.async( fn ->
          h = v.definition.service.service_health_check!(options[:health_check_options] || %{}, context, options)
          {k,h} end)]
      end)

      state = Enum.reduce(tasks, state, fn(t, acc) ->
        {k, v} = Task.await(t, await_timeout)
        Process.sleep(1_000)

        case v do
          %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{} ->
            acc
            |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:services), k], v)
          e ->
            Logger.error("#{node()} - Service Startup Error #{inspect k} - #{inspect e}")
            acc
            |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:services), k, Access.key(:status)], :error)
        end

      end)

      state = state
              |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], :online)
              |> put_in([Access.key(:environment_details), Access.key(:status)], :online)
              |> put_in([Access.key(:environment_details), Access.key(:monitors)], monitors)

      %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{
        identifier: state.environment_details.effective.identifier,
        status: state.environment_details.effective.status,
        directive: state.environment_details.effective.directive,
        health_index: state.environment_details.effective.health_index,
        entity: state.environment_details.effective
      } |> Noizu.SimplePool.Database.MonitoringFramework.NodeTable.write!()

      internal_update_hints(state.environment_details.effective, context, options)
      {:noreply, state}
    end

    def handle_call({:i, {:join, server, initial, options}, context}, from, state) do
      perform_join(state, server, from, initial, context, options)
    end

    def handle_call({:m, {:register, initial, options}, context}, _from, state) do
      initial = initial || state.environment_details.initial
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
                  |> put_in([Access.key(:environment_details), Access.key(:effective)], effective)
                  |> put_in([Access.key(:environment_details), Access.key(:default)], initial)
                  |> put_in([Access.key(:environment_details), Access.key(:status)], :registered)
          {:reply, {:ack, state.environment_details.effective}, state}
        else
          effective = remote_call(master, {:join, node(), initial, options}, context)
          state = state
                  |> put_in([Access.key(:environment_details), Access.key(:effective)], effective)
                  |> put_in([Access.key(:environment_details), Access.key(:default)], initial)
                  |> put_in([Access.key(:environment_details), Access.key(:status)], :registered)

          {:reply, {:ack, state.environment_details.effective}, state}
        end
      else
        {:reply, {:error, :master_node_required}, state}
      end
    end

    def handle_call({:i, {:node_health_check!, options}, context}, _from, state) do
      state = update_effective(state, context, options)
      {:reply, {:ack, state.environment_details.effective}, state}
    end

    def handle_call({:i, {:lock_server, components, options}, context}, _from, state) do
      await_timeout = options[:wait] || 60_000
      c = components == :all && Map.keys(state.environment_details.effective.services) || MapSet.to_list(components)

      tasks = Enum.reduce(c, [], fn(service, acc) ->
        if state.environment_details.effective.services[service] do
          acc ++ [Task.async(fn -> {service, state.environment_details.effective.services[service].definition.service.lock!(context, options)} end)]
        else
          acc
        end
      end)

      state = Enum.reduce(tasks, state, fn(task, acc) ->
        case Task.await(task, await_timeout) do
          {k, {:ack, s}} -> put_in(acc, [Access.key(:environment_details), Access.key(:effective), Access.key(:services), k], s)
          _ -> acc
        end
      end)

      %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{
        identifier: state.environment_details.effective.identifier,
        status: state.environment_details.effective.status,
        directive: state.environment_details.effective.directive,
        health_index: state.environment_details.effective.health_index,
        entity: state.environment_details.effective
      } |> Noizu.SimplePool.Database.MonitoringFramework.NodeTable.write!()

      if Map.get(options, :update_hints, true) do
        internal_update_hints(state.environment_details.effective, context, options)
      end
      {:reply, :ack, state}
    end



    def handle_call({:i, {:release_server, components, options}, context}, _from, state) do
      await_timeout = options[:wait] || 60_000
      c = components == :all && Map.keys(state.environment_details.effective.services) || MapSet.to_list(components)

      tasks = Enum.reduce(c, [], fn(service, acc) ->
        if state.environment_details.effective.services[service] do
          acc ++ [Task.async(fn -> {service, state.environment_details.effective.services[service].definition.service.release!(context, options)} end)]
        else
          acc
        end
      end)

      state = Enum.reduce(tasks, state, fn(task, acc) ->
        case Task.await(task, await_timeout) do
          {k, {:ack, s}} -> put_in(acc, [Access.key(:environment_details), Access.key(:effective), Access.key(:services), k], s)
          _ -> acc
        end
      end)

      %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{
        identifier: state.environment_details.effective.identifier,
        status: state.environment_details.effective.status,
        directive: state.environment_details.effective.directive,
        health_index: state.environment_details.effective.health_index,
        entity: state.environment_details.effective
      } |> Noizu.SimplePool.Database.MonitoringFramework.NodeTable.write!()

      if Map.get(options, :update_hints, true) do
        internal_update_hints(state.environment_details.effective, context, options)
      end
      {:reply, :ack, state}
    end


    #----------------------------------------------------------------------------
    # START| Noizu.SimplePool.MonitoringFramework.MonitorBehaviour
    #----------------------------------------------------------------------------
    @behaviour Noizu.SimplePool.MonitoringFramework.MonitorBehaviour

    def supports_service?(server, component, _context, options \\ %{}) do
      _effective = case Noizu.SimplePool.Database.MonitoringFramework.NodeTable.read!(server) do
        nil -> :nack
        v ->
          if v.entity.services[component] do
            case v.entity.services[component].status do
              :online -> :ack
              :degraded -> :ack
              :critical -> :ack
              _s ->
                if options[:system_call] do
                  :ack
                else
                  :nack
                end
            end
          else
            :nack
          end
      end
    end


    def rebalance(input_server_list, output_server_list, component_set, context, options \\ %{}) do
      # 1. Data Setup
      await_timeout = options[:wait] || 60_000
      bulk_await_timeout = options[:bulk_wait] || 1_000_000
      # Services
      cl = MapSet.to_list(component_set)
      service_list = Enum.reduce(cl, [], fn(c, acc) -> acc ++ [Module.concat([c, "Server"])] end)

      # Servers
      pool = Enum.uniq(input_server_list ++ output_server_list)


      # 2. Asynchronously grab Server rules and worker lists.
      htasks = Enum.reduce(pool, [], fn(server, acc) ->  acc ++ [Task.async(fn -> {server, server_health_check!(server, context, options)} end)] end)
      wtasks = Enum.reduce(pool, [], fn(server, acc) -> Enum.reduce(service_list, acc, fn(service, a2) -> a2 ++ [Task.async(fn -> {server, {service, service.workers!(server, context)}} end)] end) end)
      server_health = Enum.reduce(htasks, %{}, fn(task, acc) ->
        case Task.await(task, await_timeout) do
          {server, {:ack, h}} -> put_in(acc, [server], h)
          {server, error} -> put_in(acc, [server], error)
        end
      end)

      service_workers = Enum.reduce(wtasks, %{}, fn(task, acc) ->
        t = Task.await(task, await_timeout)
        case t do
          {server, {service, {:ack, workers}}} ->
            update_in(acc, [server], &(  &1 && put_in(&1, [service], workers) || %{service => workers}))
          {server, {service, error}} -> update_in(acc, [server], &(  &1 && put_in(&1, [service], error) || %{service => error}))
        end
      end)

      # 3. Prepare per server.service allocation and target details.
      service_allocation = Enum.reduce(service_workers, %{}, fn({k,v}, acc) ->
        acc = put_in(acc, [k], %{})
        Enum.reduce(v, acc, fn({k2, v2}, a2) -> put_in(a2, [k, k2], length(v2)) end)
      end)

      # 4. Calculate total available Target, Soft and Hard Limit for each service.
      per_server_targets = Enum.reduce(cl, %{}, fn(component, acc) ->
        Enum.reduce(server_health, acc, fn({server, rules}, a2) ->
          case rules do
            %Noizu.SimplePool.MonitoringFramework.Server.HealthCheck{} ->
              case rules.services[component] do
                sr = %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{} ->
                  # @TODO refactor out need to do this. pri2
                  service = Module.concat([component, "Server"])
                  a2
                  |> update_in([server], &(&1 || %{}))
                  |> put_in([server, service], %{target: sr.definition.target, soft: sr.definition.soft_limit, hard: sr.definition.hard_limit})
                _ -> a2
              end
            _ -> a2
          end
        end)
      end)


      if false do
      IO.puts """

      cl = #{inspect cl, pretty: true, limit: :infinity}
      -----------------
      services = #{inspect service_list, pretty: true, limit: :infinity}
      -----------------
      server_health = #{inspect server_health, pretty: true, limit: 15}
      -----------------
      service_workers = #{inspect service_workers, pretty: true}
      -------------
      service_allocation =  #{inspect service_allocation, pretty: true, limit: :infinity}
      --------------
      per_server_targets =  #{inspect per_server_targets, pretty: true, limit: :infinity}
      """
      end
      # 5. Calculate target allocation
      {outcome, target_allocation} = optimize_balance(input_server_list, output_server_list, service_list, per_server_targets, service_allocation)

      if false do
      IO.puts """
      ---------------------
      outcome = #{inspect outcome}
      ---------------------------
      target_allocation = #{inspect target_allocation}




      """
      end

      # include all services for any servers not in target allocation
      unallocated = Enum.reduce(pool, %{}, fn(server, acc) ->
        Enum.reduce(service_list, acc, fn(service, acc) ->
           cond do
             target_allocation[server] == nil && service_workers[server][service] -> update_in(acc, [service], &((&1 || []) ++ service_workers[server][service]))
             true -> acc
           end
        end)
      end)

      # first pass, strip overages into general pull
      {unallocated, target_allocation} = Enum.reduce(target_allocation, {unallocated, target_allocation}, fn({server, v}, {u, wa}) ->
        Enum.reduce(v, {u, wa}, fn({service, target}, {u2, wa2}) ->
          # 1. Grab any currently allocated.
          case service_workers[server][service] do
            nil -> {u2, wa2}
            workers ->
              {l, r} = Enum.split(workers, target)
              m_u2 = update_in(u2, [service], &((&1 || []) ++ r))
              m_wa2 = put_in(wa2, [server, service], (target - length(l)))
              {m_u2, m_wa2}
          end
        end)
      end)

      # second pass -> assign
      {_unallocated, final_allocation} = Enum.reduce(target_allocation, {unallocated, %{}}, fn({server, v}, {u, wa}) ->
        Enum.reduce(v, {u, wa}, fn({service, target}, {u2, wa2}) ->
          case u2[service] do
            nil -> {u2, wa2}
            workers ->
              {l, r} = Enum.split(workers, target)
              m_u2 = put_in(u2, [service], r)
              m_wa2 = wa2
                |> update_in([server], &(&1 || %{}))
                |> put_in([server, service], l)
              {m_u2, m_wa2}
          end
        end)
      end)

      # @TODO third pass - group by origin server.service
      broadcast_grouping = Enum.reduce(final_allocation, %{}, fn({server, v}, acc) ->
        Enum.reduce(v, acc, fn({service, workers}, a2) ->
          Enum.reduce(workers, a2, fn(dispatch, a3) ->
            a3
            |> update_in([dispatch.server], &(&1 || %{}))
            |> update_in([dispatch.server, service], &(&1 || %{}))
            |> update_in([dispatch.server, service, server], &((&1 || []) ++ [dispatch.identifier]))
          end)
        end)
      end)

      tasks = Enum.reduce(broadcast_grouping, [], fn({server, services}, acc) ->
        acc ++ [Task.async(fn -> {server, :rpc.call(server, __MODULE__, :server_bulk_migrate!, [services, context, options], bulk_await_timeout)} end)]
      end)

      r = Enum.reduce(tasks, %{}, fn(task, acc) ->
        {server, outcome} = Task.await(task, bulk_await_timeout)
        put_in(acc, [server], outcome)
      end)
      {:ack, r}
    end


    def server_bulk_migrate!(services, context, options) do
      await_timeout = options[:wait] || 1_000_000
      tasks = Enum.reduce(services, [], fn({service, transfer_servers}, acc) ->
        acc ++ [Task.async(fn -> {service, service.bulk_migrate!(transfer_servers, context, options)} end)]
      end)

      r = Enum.reduce(tasks, %{}, fn(task, acc) ->
        {service, outcome} = Task.await(task, await_timeout)
        put_in(acc, [service], outcome)
      end)

      {:ack, r}
    end

    def total_unallocated(unallocated) do
      Enum.reduce(unallocated, 0, fn({_service, u}, acc) -> acc + u end)
    end

    def fill_to({unallocated, service_allocation}, level, output_server_list, service_list, per_server_targets) do
      {total_bandwidth, bandwidth} = Enum.reduce(output_server_list, {%{}, %{}}, fn(server, {tb, b}) ->
        Enum.reduce(service_list, {tb, b}, fn(service, {tb2, b2}) ->
          cond do
            per_server_targets[server][service] ->
              psa = (service_allocation[server][service] || 0)
              pst = per_server_targets[server][service] || %{}
              bandwidth = case level do
                :target -> Map.get(pst, :target, 0) - psa
                :soft_limit -> Map.get(pst, :soft, 0) - psa
                :hard_limit -> Map.get(pst, :hard, 0) - psa
                :overflow -> Map.get(pst, :hard, 0)
              end |> max(0)
              m_b2 = b2
                     |> update_in([server], &(&1 || %{}))
                     |> put_in([server, service], bandwidth)
              m_tb2 = update_in(tb2, [service], &((&1 || 0) + bandwidth))
              {m_tb2, m_b2}
            true -> {tb2, b2}
          end
        end)
      end)


      # 3. Allocate out up to bandwidth to fill out to target levels
      Enum.reduce(bandwidth, {unallocated, service_allocation}, fn ({server, v}, {u, sa}) ->
        Enum.reduce(v, {u, sa}, fn({service, b}, {u2, sa2}) ->
          cond do
            b > 0 && u2[service] > 0 && total_bandwidth[service] > 0 ->
              p = min(total_bandwidth[service], unallocated[service])
              allocate = round((b/total_bandwidth[service]) * p)
              m_u2 = update_in(u2, [service], &(max(0, &1 - allocate)))
              m_sa2 = sa2 |> update_in([server], &(&1 || %{}))
                      |> update_in([server, service], &((&1 || 0) + allocate))
              {m_u2, m_sa2}
            true -> {u2, sa2}
          end
        end)
      end)
    end

    def optimize_balance(input_server_list, output_server_list, service_list, per_server_targets, service_allocation) do
      input_server_set = MapSet.new(input_server_list)
      output_server_set = MapSet.new(output_server_list)

      # 1. Calculate unallocated
      {unallocated, service_allocation} = Enum.reduce(service_allocation, {%{}, service_allocation}, fn ({server, _services}, {u,sa}) ->
        cond do
          !MapSet.member?(input_server_set, server) && MapSet.member?(output_server_set, server) -> {u, sa}
          true ->
            {w, m_sa} = pop_in(sa, [server])
            m_u = Enum.reduce(w, u, fn({service, worker_count}, acc) -> update_in(acc, [service], &((&1 || 0) + worker_count)) end)
            {m_u, m_sa}
        end
      end)

      # 2. Fill up to target
      {unallocated, service_allocation} = fill_to({unallocated, service_allocation}, :target, output_server_list, service_list, per_server_targets)
      r = total_unallocated(unallocated)
      cond do
        r == 0 -> {:target, service_allocation}
        true -> # 3. Fill up to soft_limit
          {unallocated, service_allocation} = fill_to({unallocated, service_allocation}, :soft_limit, output_server_list, service_list, per_server_targets)
          r2 = total_unallocated(unallocated)
          cond do
            r2 == 0 -> {:soft_limit, service_allocation}
            true -> # 3. Fill up to hard_limit
              {unallocated, service_allocation} = fill_to({unallocated, service_allocation}, :hard_limit, output_server_list, service_list, per_server_targets)
              r3 = total_unallocated(unallocated)
              cond do
                r3 == 0 -> {:hard_limit, service_allocation}
                true -> # 4. overflow!
                  {unallocated, service_allocation} = fill_to({unallocated, service_allocation}, :overflow, output_server_list, service_list, per_server_targets)
                  r4 = total_unallocated(unallocated)
                  cond do
                    r4 < 0 -> {{:error, :critical_bug}, service_allocation}
                    r4 == 0 -> {:overflow, service_allocation}
                    r4 > 0 ->
                      # @TODO add check for unassignable services higher in logic. (we can check as soon as we output server health checks)
                      {{:error, :unassignable_services}, service_allocation}
                  end
              end
          end
      end
    end

    def lock_server(context), do: lock_servers([node()], :all, context, %{})
    def lock_server(context, options), do: lock_servers([node()], :all, context, options)
    def lock_server(components, context, options), do: lock_servers([node()], components, context, options)
    def lock_server(server, components, context, options), do: lock_servers([server], components, context, options)

    def lock_servers(servers, components, context, options \\ %{}) do
      await_timeout = options[:wait] || 60_000
      options_b = Map.has_key?(options, :update_hints) && options || put_in(options, [:update_hints], false)
      locks = for server <- servers, do:  Task.async(fn -> remote_call(server, {:lock_server, components, options_b}, context, options_b) end)
      for lock <- locks, do: Task.await(lock, await_timeout)
      if Map.get(options, :update_hints, true), do: internal_update_hints(components, context, options)
      :ack
    end

    def release_server(context), do: release_servers([node()], :all, context, %{})
    def release_server(context, options), do: release_servers([node()], :all, context, options)
    def release_server(components, context, options), do: release_servers([node()], components, context, options)
    def release_server(server, components, context, options), do: release_servers([server], components, context, options)

    def release_servers(servers, components, context, options \\ %{}) do
      await_timeout = options[:wait] || 60_000
      options_b = Map.has_key?(options, :update_hints) && options || put_in(options, [:update_hints], false)
      locks = for server <- servers, do: Task.async(fn -> remote_call(server, {:release_server, components, options}, context, options_b) end)
      for lock <- locks, do: Task.await(lock, await_timeout)
      if Map.get(options, :update_hints, true), do: internal_update_hints(components, context, options)
      :ack
    end

    def select_host(_ref, component, _context, _options \\ %{}) do
      case Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable.read!(component) do
        nil -> {:nack, :hint_required}
        v ->
          if v.status === %{} do
            {:nack, :none_available}
          else
            if Enum.empty?(v.hint) do
              {:nack, :none_available}
            else
              # TODO handle no hints, illegal format, etc.
              {{host, _service}, _v} = Enum.random(v.hint)
              {:ack, host}
            end
          end
      end
    end

    def record_server_event!(server, event, details, _context, options \\ %{}) do
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

    def record_service_event!(server, service, event, details, _context, options \\ %{}) do
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

    def handle_info({:DOWN, ref, :process, _process, _msg} = event, state) do
      Logger.info "LINK MONITOR: #{inspect event, pretty: true}"
      monitors = Enum.reduce(state.environment_details.monitors, %{}, fn({k,v}, acc) ->
        if ref == v do
          Map.put(acc, k, nil)
        else
          Map.put(acc, k, v)
        end
      end)
      state = put_in(state, [Access.key(:environment_details), Access.key(:monitors)], monitors)
      {:noreply, state}
    end

    alias Noizu.SimplePool.Server.State
    alias Noizu.SimplePool.Server.EnvironmentDetails

    def init([_sup, definition, context] = _args) do
      if verbose() do
        Logger.info(fn -> {base().banner("INIT #{__MODULE__} (#{inspect Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor}@#{inspect self()})"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
      end

      # @TODO load real effective PRI-1
      effective = %{}

      Logger.info "INIT #{inspect definition}"
      state = %State{
        worker_supervisor: Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor, # @TODO should be worker_supervisor
        service: Noizu.MonitoringFramework.EnvironmentPool.Server, # @TODO should be service
        status_details: :pending,
        extended: %{monitors: %{}},
        options: option_settings(),
        environment_details: %EnvironmentDetails{
          server: node(),
          definition: definition,
          initial: definition.server_options.initial,
          effective: effective,
          default: nil,
          status: :offline,
          monitors: %{}
        }
      }
      {:ok, state}
    end

    #---------------------------------------------------------------------------
    # Convenience Methods
    #---------------------------------------------------------------------------
    def register(initial, context, options \\ %{}) do
      GenServer.call(__MODULE__, {:m, {:register, initial, options}, context}, 60_000)
    end

    def start_services(context, options \\ %{}) do
      GenServer.cast(__MODULE__, {:m, {:start_services, options}, context})
    end

    def update_hints!(context, options \\ %{}) do
      internal_system_cast({:update_hints, options}, context)
    end


    def internal_update_hints(components, context, options \\ %{})
    def internal_update_hints(:all, context, options) do
      internal_system_cast({:prep_hint_update, :all, options}, context, options)
    end

    def internal_update_hints(%MapSet{} = components, context, options) do
      internal_system_cast({:prep_hint_update, components, options}, context, options)
    end

    def internal_update_hints(effective, context, options) do
      remote_system_cast(effective.master_node, {:hint_update, effective, options}, context, options)
    end



    #---------------------------------------------------------------------------
    # Handlers
    #---------------------------------------------------------------------------
    def perform_join(state, server, {pid, _ref}, initial, _context, _options) do

      effective = case Noizu.SimplePool.Database.MonitoringFramework.NodeTable.read!(server) do
        nil -> initial
        v -> v.entity
      end

      effective = put_in(effective, [Access.key(:master_node)], node())

      _s = %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{
            identifier: effective.identifier,
            status: effective.status,
            directive: effective.directive,
            health_index: effective.health_index,
            entity: effective
          } |> Noizu.SimplePool.Database.MonitoringFramework.NodeTable.write!()

      monitor_ref = Process.monitor(pid)
      put_in(state, [Access.key(:extended), Access.key(:monitors), server], monitor_ref)
      {:reply, effective, state}
    end




    def update_effective(state, context, options) do
      await_timeout = options[:wait] || 60_000
      tasks = Enum.reduce(state.environment_details.effective.services, [], fn({k,v}, acc) ->
        acc ++ [Task.async( fn ->
          h = v.definition.service.service_health_check!(options[:health_check_options] || %{}, context, options)
          {k,h} end)]
      end)

      effective = Enum.reduce(tasks, state.environment_details.effective, fn(t, acc) ->
        {k, v} = Task.await(t, await_timeout)
        put_in(acc, [Access.key(:services), k], v)
      end)

      state = put_in(state, [Access.key(:environment_details), Access.key(:effective)], effective)
      state
    end


    def server_health_check!(server, context, options) do
      :rpc.call(server, __MODULE__, :server_health_check!, [context, options])
    end

    def server_health_check!(context, options) do
      internal_system_call({:node_health_check!, options[:node_health_check!] || %{}}, context, options)
    end

    def node_health_check!(context, options) do
      server_health_check!(context, options)
    end

    def perform_hint_update(state, components, context, options) do
      await_timeout = options[:wait] || 60_000
      # call each service node to get current health checks.
      # 1. Grab nodes
      servers_raw = Amnesia.Fragment.async(fn ->
        Noizu.SimplePool.Database.MonitoringFramework.NodeTable.where(1 == 1)
        |> Amnesia.Selection.values
      end)
      state = update_effective(state, context, options)

      # 2. Grab Server Status
      tasks = Enum.reduce(servers_raw, [], fn(x, acc) ->
        if (x.identifier != node()) do
          task = Task.async( fn ->
            {x.identifier, :rpc.call(x.identifier, __MODULE__, :node_health_check!, [context, options])}
          end)
          acc ++ [task]
        else
          task = Task.async( fn -> {x.identifier, {:ack, state.environment_details.effective}} end)
          acc ++ [task]
        end
      end)

      servers = Enum.reduce(tasks, %{}, fn (task, acc) ->
        {k, {:ack, v}} = Task.await(task, await_timeout)
        Map.put(acc, k, v)
      end)

      # 3. Calculate Hints
      valid_status = MapSet.new([:online, :degraded, :critical])
      valid_status_weight = %{online: 1, degraded: 2, critical: 3}

      update = case components do
        %MapSet{} -> MapSet.to_list(components)
        :all -> Enum.reduce(servers_raw, MapSet.new([]), fn(x, acc) ->
          MapSet.union(acc, MapSet.new(Map.keys(x.entity.services)))
        end) |> MapSet.to_list()
        %Noizu.SimplePool.MonitoringFramework.Server.HealthCheck{} -> Map.keys(components.services)
      end

      Enum.reduce(update, true, fn(service, _acc) ->
        candidates = Enum.reduce(servers, [], fn ({_server_id, server}, acc2) ->
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




  end # end defmodule GoldenRatio.Components.Gateway.Server
end # end defmodule GoldenRatio.Components.Gateway
