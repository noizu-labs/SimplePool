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
    @doc """
      Responsible for system wide management of services, worker migration and other critical tasks.
    """
    @vsn 1.0
    #@monitor_ms 60 * 5 * 1000
    @master_node_cache_key :"noizu:active_master_node"

    alias Noizu.SimplePool.Server.State
    alias Noizu.SimplePool.Server.EnvironmentDetails

    use Noizu.SimplePool.ServerBehaviour,
        worker_state_entity: Noizu.MonitoringFramework.EnvironmentWorkerEntity,
        override: [:init]

    @behaviour Noizu.SimplePool.MonitoringFramework.MonitorBehaviour


    #================================================
    # LifeCycle Methods
    #================================================

    #--------------------------------------
    #
    #--------------------------------------
    def init([_sup, definition, context] = _args) do
      if verbose() do
        Logger.info(fn -> {base().banner("INIT #{__MODULE__} (#{inspect Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor}@#{inspect self()})"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
      end

      # @TODO load real effective PRI-1
      effective = nil

      Logger.info fn() -> {"INIT #{inspect definition}", Noizu.ElixirCore.CallingContext.metadata(context)} end
                          state = %State{
                            worker_supervisor: Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor, # @TODO should be worker_supervisor
                            service: Noizu.MonitoringFramework.EnvironmentPool.Server, # @TODO should be service
                            status_details: :pending,
                            extended: %{monitors: %{}, watchers: %{}},
                            options: option_settings(),
                            environment_details: %EnvironmentDetails{
                              server: node(),
                              definition: definition,
                              initial: definition && definition.server_options && definition.server_options.initial || %{},
                              effective: effective || definition && definition.server_options && definition.server_options.initial || %{},
                              default: nil,
                              status: :offline,
                              monitors: %{}
                            }
                          }

                          enable_server!()
                          {:ok, state}
      end

      #================================================
      # Convenience Methods
      #================================================

      #--------------------------------------
      #
      #--------------------------------------
      def register(initial, context, options \\ %{}) do
        GenServer.call(__MODULE__, {:m, {:register, initial, options}, context}, 60_000)
      end

      #--------------------------------------
      #
      #--------------------------------------
      def start_services(context, options \\ %{}) do
        GenServer.cast(__MODULE__, {:m, {:start_services, options}, context})
      end

      #--------------------------------------
      #
      #--------------------------------------
      def update_hints!(context, options \\ %{}) do
        internal_system_cast({:update_hints, options}, context)
      end

      #--------------------------------------
      #
      #--------------------------------------
      def internal_update_hints(components, context, options \\ %{})
      def internal_update_hints(:all, context, options) do
        internal_system_cast({:prep_hint_update, :all, options}, context, options)
      end

      #--------------------------------------
      #
      #--------------------------------------
      def internal_update_hints(%MapSet{} = components, context, options) do
        internal_system_cast({:prep_hint_update, components, options}, context, options)
      end

      #--------------------------------------
      #
      #--------------------------------------
      def internal_update_hints(effective, context, options) do
        remote_system_cast(master_node(effective), {:hint_update, effective, options}, context, options)
      end

      #--------------------------------------
      #
      #--------------------------------------
      def fetch_internal_state(server, context, options) do
        :rpc.call(server, __MODULE__, :fetch_internal_state, [context, options])
      end

      def fetch_internal_state(context, options) do
        internal_system_call({:fetch_internal_state, options}, context, options)
      end

      #--------------------------------------
      #
      #--------------------------------------
      def set_internal_state(server, state, context, options) do
        :rpc.call(server, __MODULE__, :set_internal_state, [state, context, options])
      end

      def set_internal_state(state, context, options) do
        internal_system_call({:set_internal_state, state, options}, context, options)
      end

      #--------------------------------------
      #
      #--------------------------------------
      def update_master_node(master_node, context, options) do
        spawn fn ->
          # Clear FastGlobal Cache
          FastGlobal.put(@master_node_cache_key, master_node)

          # Update Database Entry
          Noizu.SimplePool.Database.MonitoringFramework.SettingTable.delete!(:environment_master)
          %Noizu.SimplePool.Database.MonitoringFramework.SettingTable{setting: :environment_master, value: master_node}
          |>  Noizu.SimplePool.Database.MonitoringFramework.SettingTable.write!()

          Node.list()
          |> Task.async_stream(&(:rpc.cast(&1, FastGlobal, :put, [@master_node_cache_key, master_node])))
        end

        # Call servers to update state entities
        call = {:update_master_node, master_node, options}
        internal_system_cast(call, context, options)
        spawn fn ->
          Node.list()
          |> Task.async_stream(&( :rpc.cast(&1, __MODULE__, :internal_system_cast, [call, context, options])))
        end

        master_node
      end

      #============================================================================
      # Noizu.SimplePool.MonitoringFramework.MonitorBehaviour Implementation
      #============================================================================

      #--------------------------------------
      #
      #--------------------------------------
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

      #--------------------------------------
      #
      #--------------------------------------
      def optomized_rebalance(input_server_list, output_server_list, component_set, context, options \\ %{}) do
        pfs = profile_start(%{}, :optomized_rebalance)
        #--------------------
        # 1. Data Setup
        #--------------------
        pfs = profile_start(pfs, :data_setup)
        await_timeout = options[:wait] || 60_000
        bulk_await_timeout = options[:bulk_wait] || 1_000_000
        # Services
        component_list = MapSet.to_list(component_set)
        service_list = Enum.map(component_list, fn(c) -> Module.concat([c, "Server"]) end)
        # Servers
        pool = Enum.uniq(input_server_list ++ output_server_list)
        pfs = profile_end(pfs, :data_setup)

        #------------------------------------------------------
        # 2. Asynchronously grab Server rules and worker lists.
        #------------------------------------------------------
        pfs = profile_start(pfs, :fetch_worker_list)
        htasks = Task.async_stream(pool, fn(server) -> {server, server_health_check!(server, context, options)} end, timeout: await_timeout)
        wtasks = pool
                 |> Enum.map(fn(server) -> Enum.map(service_list, fn(service) -> {server, service} end) end)
                 |> List.flatten()
                 |> Task.async_stream(fn({server, service}) -> {server, {service, service.workers!(server, context)}} end, timeout: await_timeout)
        {server_health, _server_health_errors} = Enum.reduce(htasks, {%{}, %{}}, fn(outcome, {acc, ecc}) ->
          case outcome do
            {:ok, {server, {:ack, h}}} -> {put_in(acc, [server], h), ecc}
            {:ok, {server, error}} -> {acc, put_in(ecc, [server], error)}
            e -> {acc, update_in(ecc, [:unknown], &((&1 || []) ++ [e]))}
          end
        end)
        {service_workers, _service_workers_errors, _i} = Enum.reduce(wtasks, {%{}, %{}, 0}, fn(outcome, {acc, ecc, i}) ->
          case outcome do
            {:ok, {server, {service, {:ack, workers}}}} -> {put_in(acc, [{server, service}], %{workers: workers, allocation: length(workers)}), ecc, i + 1}
            {:ok, {server, {service, error}}} -> {acc, put_in(ecc, [{server, service}], error), i + 1}
            e -> {acc, update_in(ecc, [:unknown], &((&1 || []) ++ [{i, e}])), i + 1}
          end
        end)
        pfs = profile_end(pfs, :fetch_worker_list, %{info: 30_000, warn: 60_000, error: 90_000})

        #------------------------------------------------------------------
        # 3. Prepare per server.service allocation and target details.
        #------------------------------------------------------------------
        pfs = profile_start(pfs, :service_allocation)
        component_service_map = Enum.reduce(component_list, %{}, fn(x, acc) -> put_in(acc, [x], Module.concat([x, "Server"])) end)
        per_server_targets = Enum.reduce(server_health, %{}, fn({server, rules}, acc) ->
          case rules do
            %Noizu.SimplePool.MonitoringFramework.Server.HealthCheck{} ->
              server_targets = Enum.reduce(component_list, %{}, fn(component, sa) ->
                case rules.services[component] do
                  sr = %Noizu.SimplePool.MonitoringFramework.Service.HealthCheck{} ->
                    # @TODO refactor out need to do this. pri2
                    put_in(sa, [component_service_map[component]], %{target: sr.definition.target, soft: sr.definition.soft_limit, hard: sr.definition.hard_limit})
                  _ -> sa
                end
              end)
              put_in(acc, [server], server_targets)
            _ -> acc
          end
        end)

        # 5. Calculate target allocation
        service_allocation = Enum.reduce(Map.keys(service_workers), %{}, fn({server, service} = k, acc) ->
          v = service_workers[k].allocation
          update_in(acc, [server], fn(p) -> p && put_in(p, [service], v) || %{service => v} end)
        end)
        {_outcome, target_allocation} = optimize_balance(input_server_list, output_server_list, service_list, per_server_targets, service_allocation)

        # include all services for any servers not in target allocation
        pull_servers = input_server_list -- output_server_list
        unallocated = Enum.reduce(service_list, %{}, fn(service, acc) -> put_in(acc, [service], Enum.map([pull_servers], fn(server) -> service_workers[{server, service}][:workers] || [] end) |> List.flatten()) end)

        # first pass, strip overages into general pull
        {additional_unallocated, target_allocation} = Enum.reduce(target_allocation, {%{}, target_allocation}, fn({server, v}, {u, wa}) ->
          Enum.reduce(v, {u, wa}, fn({service, target}, {u2, wa2}) ->
            # 1. Grab any currently allocated.
            allocation = service_workers[{server, service}][:allocation]
            cond do
              allocation == nil -> {u2, wa2}
              allocation < target ->
                {u2, put_in(wa2, [server, service], (target - allocation))}
              true ->
                {_l, r} = Enum.split(service_workers[{server, service}][:workers], target)
                m_u2 = update_in(u2, [service], &((&1 || []) ++ r))
                m_wa2 = put_in(wa2, [server, service], 0)
                {m_u2, m_wa2}
            end
          end)
        end)

        # second pass -> assign
        final_allocation = Enum.reduce(service_list, %{}, fn(service, acc) ->
          su = (unallocated[service] || []) ++ (additional_unallocated[service] || [])
          {_u, uacc} = Enum.reduce(target_allocation, {su, acc}, fn({server, v}, {u, wa}) ->
            cond do
              u == nil || u == [] -> {u, wa}
              v[service] > 0 ->
                {l, r} = Enum.split(u, v[service])
                {r, put_in(wa, [{server, service}], l)}
              true -> {u, wa}
            end
          end)
          uacc
        end)
        pfs = profile_end(pfs, :service_allocation, %{info: 30_000, warn: 60_000, error: 90_000})

        #------------
        # Dispatch
        #----------------
        pfs = profile_start(pfs, :dispatch)

        # @TODO third pass - group by origin server.service
        broadcast_grouping = Enum.reduce(final_allocation, %{}, fn({{server, service}, workers}, acc) ->


          Enum.reduce(workers, acc, fn(worker, acc) ->
            cond do
              acc[worker.server][service][server] -> update_in(acc, [worker.server, service, server], &(&1 ++ [worker.identifier]))
              acc[worker.server][service] -> put_in(acc, [worker.server, service, server], [worker.identifier])
              acc[worker.server] -> put_in(acc, [worker.server, service], %{server => [worker.identifier]})
              true -> put_in(acc, [worker.server], %{service => %{server => [worker.identifier]}})
            end
          end)

        end)

        tasks = Task.async_stream(broadcast_grouping, fn({server, services}) -> {server, :rpc.call(server, __MODULE__, :server_bulk_migrate!, [services, context, options], bulk_await_timeout)} end, timeout: bulk_await_timeout)
        r = Enum.map(tasks, &(&1))
        #r = []
        pfs = profile_end(pfs, :dispatch, %{info: 30_000, warn: 60_000, error: 90_000})
        pfs = profile_end(pfs, :optomized_rebalance, %{info: 30_000, warn: 60_000, error: 90_000})
        {:ack, {r, pfs}}
      end

      #--------------------------------------
      #
      #--------------------------------------
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
            _ -> acc
          end
        end)

        service_workers = Enum.reduce(wtasks, %{}, fn(task, acc) ->
          t = Task.await(task, await_timeout)
          case t do
            {server, {service, {:ack, workers}}} ->
              update_in(acc, [server], &(  &1 && put_in(&1, [service], workers) || %{service => workers}))
            {server, {service, error}} -> update_in(acc, [server], &(  &1 && put_in(&1, [service], error) || %{service => error}))
            _ -> acc
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

        {:ack, Enum.reduce(tasks, %{}, fn(task, acc) ->
          case Task.await(task, await_timeout) do
            {service, {:ack, outcome}} ->


              o = Enum.reduce(outcome, [],
                fn({_k, {:ack, v}} = _x ,a) ->

                  cond do
                    options[:return_worrkers] ->
                      process_map = for {server, v2} <- v do
                                      for e <- v2 do
                                        case e do
                                          {:ok, {ref, {:ack, pid}}} -> [{server, ref, pid}]
                                          _ -> {server, :error}
                                        end
                                      end
                                    end |> List.flatten

                      a ++ process_map

                    true -> a ++ Map.keys(v)
                  end

                end)


              put_in(acc, [service], o)
            _ -> acc
          end
        end)
        }



      end


      #--------------------------------------
      #
      #--------------------------------------
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

      #--------------------------------------
      #
      #--------------------------------------
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


      #--------------------------------------
      #
      #--------------------------------------
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


      #--------------------------------------
      #
      #--------------------------------------
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

      #--------------------------------------
      #
      #--------------------------------------
      def select_host(_ref, component, _context, options \\ %{}) do
        case Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable.read!(component) do
          nil -> {:nack, :hint_required}
          v ->
            if v.status === %{} do
              {:nack, :none_available}
            else
              if Enum.empty?(v.hint) do
                {:nack, :none_available}
              else
                if options[:sticky] do
                  n = case options[:sticky] do
                        true -> node()
                        v -> v
                      end
                  case Enum.find(v.hint, fn({{host, _service}, _v}) -> host == n end) do
                    {{host, _service}, _v} -> {:ack, host}
                    _ ->
                      {{host, _service}, _v} = Enum.random(v.hint)
                      {:ack, host}
                  end
                else
                  # TODO handle no hints, illegal format, etc.
                  {{host, _service}, _v} = Enum.random(v.hint)
                  {:ack, host}
                end
              end
            end
        end
      end

      #--------------------------------------
      #
      #--------------------------------------
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


      #--------------------------------------
      #
      #--------------------------------------
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


      #--------------------------------------
      #
      #--------------------------------------
      def update_effective(state, context, options) do
        case state.environment_details && state.environment_details.effective do
          %Noizu.SimplePool.MonitoringFramework.Server.HealthCheck{} ->
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
          _ ->
            Logger.error "#{__MODULE__}.update_effective Malformed State: #{inspect state, pretty: true, limit: :infinity}\n", Noizu.ElixirCore.CallingContext.metadata(context)
            state
        end
      end

      #--------------------------------------
      #
      #--------------------------------------
      def server_health_check!(server, context, options) do
        :rpc.call(server, __MODULE__, :server_health_check!, [context, options])
      end

      #--------------------------------------
      #
      #--------------------------------------
      def server_health_check!(context, options) do
        internal_system_call({:node_health_check!, options[:node_health_check!] || %{}}, context, options)
      end

      #--------------------------------------
      #
      #--------------------------------------
      def node_health_check!(context, options) do
        server_health_check!(context, options)
      end

      #================================================
      # Call Handlers
      #================================================


      #--------------------------------------
      #
      #--------------------------------------
      def handle_cast({:i, {:update_hints, options}, context}, state) do
        internal_update_hints(state.environment_details.effective, context, options)
        {:noreply, state}
      end

      #--------------------------------------
      #
      #--------------------------------------
      def handle_cast({:i, {:prep_hint_update, components, options}, context}, state) do
        remote_system_cast(master_node(state), {:hint_update, components, options}, context)
        {:noreply, state}
      end

      #--------------------------------------
      #
      #--------------------------------------
      def handle_cast({:i, {:hint_update, components, options}, context}, state) do
        perform_hint_update(state, components, context, options)
      end

      #--------------------------------------
      #  perform_join | Noizu.SimplePool.MonitoringFramework.MonitorBehaviour Implementation
      #--------------------------------------
      def perform_join(state, server, {pid, _ref}, initial, _context, options) do
        effective = cond do
                      options[:update_node] -> initial
                      true ->
                        case Noizu.SimplePool.Database.MonitoringFramework.NodeTable.read!(server) do
                          nil -> initial
                          v = %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{} -> v.entity
                        end
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

      #--------------------------------------
      #
      #--------------------------------------
      def perform_hint_update(state, components, context, options) do
        await_timeout = options[:wait] || 60_000
        # call each service node to get current health checks.
        # 1. Grab nodes
        servers_raw = Amnesia.Fragment.async(fn ->
          Noizu.SimplePool.Database.MonitoringFramework.NodeTable.where(1 == 1)  |> Amnesia.Selection.values
        end)

        state = try do
                  update_effective(state, context, options)
        rescue _e -> state
                end

        # 2. Grab Server Status
        tasks = Enum.reduce(servers_raw, [], fn(x, acc) ->
          if (x.identifier != node()) do
            task = Task.async( fn ->
              {x.identifier, server_health_check!(x.identifier, context, options)}
            end)
            acc ++ [task]
          else
            task = Task.async( fn -> {x.identifier, {:ack, state.environment_details.effective}} end)
            acc ++ [task]
          end
        end)

        servers = Enum.reduce(tasks, %{}, fn (task, acc) ->
          case Task.await(task, await_timeout) do
            {k, {:ack, v}} -> Map.put(acc, k, v)
            _ -> acc
          end
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

          # 1. add a minimum of 1/3rd of the nodes and all good nodes.
          candidate_pool_size = length(candidates)
          min_bar = max(div(candidate_pool_size, 3), 1)

          # first pass, grab best servers only.
          hint = Enum.reduce(candidates, [], fn(x, acc3) ->
            cond do
              x.server_status == :online && x.service_status == :online ->  acc3 ++ [x]
              true -> acc3
            end
          end)

          # second pass, include degraded
          hint = Enum.reduce(candidates -- hint, hint, fn(x,acc3) ->
            cond do
              length(acc3) >= min_bar -> acc3
              x.server_status == :online && Enum.member?([:online, :degraded], x.service_status)->  acc3 ++ [x]
              true -> acc3
            end
          end)

          # third pass, include critical
          hint = Enum.reduce(candidates -- hint, hint, fn(x,acc3) ->
            cond do
              length(acc3) >= min_bar -> acc3
              x.server_status == :online && Enum.member?([:online, :degraded, :critical], x.service_status)->  acc3 ++ [x]
              true -> acc3
            end
          end)

          # fourth pass, any online server
          hint = Enum.reduce(candidates -- hint, hint, fn(x,acc3) ->
            cond do
              length(acc3) >= min_bar -> acc3
              x.server_status == :online ->  acc3 ++ [x]
              true -> acc3
            end
          end)

          # final pass, insure minbar
          hint = Enum.reduce(candidates -- hint, hint, fn(x,acc3) ->
            cond do
              length(acc3) >= min_bar -> acc3
              true -> acc3 ++ [x]
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

      #--------------------------------------
      #
      #--------------------------------------
      def handle_cast({:i, {:update_master_node, master_node, _options}, _context}, state) do
        state = cond do
                  state == nil -> state
                  state.environment_details == nil -> state
                  state.environment_details.effective == nil -> state
                  true ->
                    put_in(state, [Access.key(:environment_details), Access.key(:effective), Access.key(:master_node)], master_node)
                end
        {:noreply, state}
      end

      #--------------------------------------
      #
      #--------------------------------------
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
              Logger.error("#{node()} - Service Startup Error #{inspect k} - #{inspect e}", Noizu.ElixirCore.CallingContext.metadata(context))
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

      #--------------------------------------
      #
      #--------------------------------------
      def handle_call({:i, {:fetch_internal_state, _options}, _context}, _from, state) do
        {:reply, state, state, :hibernate}
      end

      #--------------------------------------
      #
      #--------------------------------------
      def handle_call({:i, {:set_internal_state, update, _options}, _context}, _from, state) do
        {:reply, %{old: state, new: update}, update, :hibernate}
      end

      #--------------------------------------
      #
      #--------------------------------------
      def handle_call({:i, {:join, server, initial, options}, context}, from, state) do
        perform_join(state, server, from, initial, context, options)
      end

      #--------------------------------------
      #
      #--------------------------------------
      def handle_call({:m, {:register, initial, options}, context}, _from, state) do
        initial = initial || state.environment_details.initial
        master = cond do
                   v = master_node(state) ->
                     cond do
                       v == :self -> update_master_node(node(), context, %{}) # This may be problematic.
                       :else -> v
                     end
                   initial.master_node == :self || initial.master_node == node() -> update_master_node(node(), context, %{})
                   :else -> nil
                 end

        if master do
          if master == node() do
            effective = cond do
                          options[:update_node] -> initial
                          true ->
                            case Noizu.SimplePool.Database.MonitoringFramework.NodeTable.read!(node()) do
                              nil -> initial
                              v = %Noizu.SimplePool.Database.MonitoringFramework.NodeTable{} -> v.entity
                              _ -> initial
                            end
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

      #--------------------------------------
      #
      #--------------------------------------
      def handle_call({:i, {:node_health_check!, options}, context}, _from, state) do
        state = update_effective(state, context, options)
        {:reply, {:ack, state.environment_details.effective}, state}
      end

      #--------------------------------------
      #
      #--------------------------------------
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

      #--------------------------------------
      #
      #--------------------------------------
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

      #--------------------------------------
      #
      #--------------------------------------
      def handle_info({:i, {:server_recover_check, _server}, _context}, state) do
        # @TODO fully implement
        {:noreply, state}
      end

      #--------------------------------------
      #
      #--------------------------------------
      def handle_info({:DOWN, ref, :process, _process, _msg} = event, state) do
        state = cond do
                  dropped_server = Enum.find(state.environment_details.monitors, fn({_k,v}) -> v == ref end) ->
                    {server, _ref} = dropped_server
                    Logger.error "LINK MONITOR: server down #{inspect server} - #{inspect event, pretty: true}"
                    # todo setup watchers[server] with a timer event that monitors for node recovery
                    #{:ok, t_ref} = :timer.send_after(@monitor_ms, self(), {:i, {:server_recover_check, server}, Noizu.ElixirCore.CallingContext.system()})
                    state
                    |> put_in([Access.key(:environment_details), Access.key(:monitors), server], nil)
                  #|> update_in([Access.key(:extended), :watchers], &(put_in(&1 || %{}, [server], t_ref)))
                  true ->
                    Logger.error "LINK MONITOR: #{inspect event, pretty: true}"
                    state
                end
        {:noreply, state}
      end


      #===========================================================================
      # Helper Methods
      #===========================================================================

      #--------------------------------------
      #
      #--------------------------------------
      def total_unallocated(unallocated) do
        Enum.reduce(unallocated, 0, fn({_service, u}, acc) -> acc + u end)
      end

      #--------------------------------------
      #
      #--------------------------------------
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


      #--------------------------------------
      #
      #--------------------------------------
      def profile_start(profiles \\ %{}, profile \\ :default) do
        put_in(profiles, [profile], %{start: :os.system_time(:millisecond)})
      end


      #--------------------------------------
      #
      #--------------------------------------
      def profile_end(profiles, profile \\ :default, options \\ %{info: 100, warn: 300, error: 700, log: true}) do
        profiles = update_in(profiles, [profile], fn(p) -> put_in(p || %{}, [:end], :os.system_time(:millisecond)) end)
        if options[:log] !== false do
          cond do
            profiles[profile][:start] == nil -> Logger.warn("#{__MODULE__} - profile_start not invoked for #{profile}")
            options[:error] && (profiles[profile][:end] - profiles[profile][:start]) >= options[:error] ->
              Logger.error("#{__MODULE__} #{profile} exceeded #{options[:error]} milliseconds @#{(profiles[profile][:end] - profiles[profile][:start])}")
            options[:warn] && (profiles[profile][:end] - profiles[profile][:start]) >= options[:warn] ->
              Logger.warn(fn -> "#{__MODULE__} #{profile} exceeded #{options[:warn]} milliseconds @#{(profiles[profile][:end] - profiles[profile][:start])}"  end)
            options[:info] && (profiles[profile][:end] - profiles[profile][:start]) >= options[:info] ->
              Logger.info(fn -> "#{__MODULE__} #{profile} exceeded #{options[:info]} milliseconds @#{(profiles[profile][:end] - profiles[profile][:start])}"  end)
            true -> :ok
          end
        end
        profiles
      end

      #--------------------------------------
      #
      #--------------------------------------
      def master_node(%State{} = state) do
        fg_get(@master_node_cache_key,
          fn() ->
            default = try do
                        cond do
                          state == nil -> {:fast_global, :no_cache, nil}
                          state.environment_details == nil -> {:fast_global, :no_cache, nil}
                          state.environment_details.effective == nil -> {:fast_global, :no_cache, nil}
                          v = state.environment_details.effective.master_node -> v
                          true -> {:fast_global, :no_cache, nil}
                        end
            rescue _e -> {:fast_global, :no_cache, nil}
            catch _e -> {:fast_global, :no_cache, nil}
                      end

            if Noizu.SimplePool.Database.MonitoringFramework.SettingTable.wait(500) == :ok do
              case Noizu.SimplePool.Database.MonitoringFramework.SettingTable.read!(:environment_master) do
                [%Noizu.SimplePool.Database.MonitoringFramework.SettingTable{value: v}| _] -> v
                %Noizu.SimplePool.Database.MonitoringFramework.SettingTable{value: v} -> v
                nil -> default
                _ -> default
              end
            else
              default
            end
          end
        )
      end

      def master_node(%{master_node: default} = _state) do
        fg_get(@master_node_cache_key,
          fn() ->
            default = {:fast_global, :no_cache, default}
            if Noizu.SimplePool.Database.MonitoringFramework.SettingTable.wait(500) == :ok do
              case Noizu.SimplePool.Database.MonitoringFramework.SettingTable.read!(:environment_master) do
                [%Noizu.SimplePool.Database.MonitoringFramework.SettingTable{value: v}| _] -> v
                %Noizu.SimplePool.Database.MonitoringFramework.SettingTable{value: v} -> v
                nil -> default
                _ -> default
              end
            else
              default
            end
          end
        )
      end

      def master_node(_catch_all) do
        fg_get(@master_node_cache_key,
          fn() ->
            default = {:fast_global, :no_cache, nil}
            if Noizu.SimplePool.Database.MonitoringFramework.SettingTable.wait(500) == :ok do
              case Noizu.SimplePool.Database.MonitoringFramework.SettingTable.read!(:environment_master) do
                [%Noizu.SimplePool.Database.MonitoringFramework.SettingTable{value: v}| _] -> v
                %Noizu.SimplePool.Database.MonitoringFramework.SettingTable{value: v} -> v
                nil -> default
                _ -> default
              end
            else
              default
            end
          end
        )
      end


      #--------------------
      # todo move FastGlobal.Cluster into Noizu Core and remove duplicate code.
      #--------------------

      #-------------------
      # fg_get
      #-------------------
      def fg_get(identifier), do: fg_get(identifier, nil, %{})
      def fg_get(identifier, default), do: fg_get(identifier, default, %{})
      def fg_get(identifier, default, options) do
        case FastGlobal.get(identifier, :no_match) do
          :no_match -> fg_sync_record(identifier, default, options)
          v -> v
        end
      end


      #-------------------
      # sync_record
      #-------------------
      def fg_sync_record(identifier, default, _options) do
        value = if (is_function(default, 0)), do: default.(), else: default
        case value do
          {:fast_global, :no_cache, v} -> v
          value ->
            if Semaphore.acquire({:fg_write_record, identifier}, 1) do
              FastGlobal.put(identifier, value)
              Semaphore.release({:fg_write_record, identifier})
            end
            value
        end
      end

    end # end defmodule GoldenRatio.Components.Gateway.Server
  end # end defmodule GoldenRatio.Components.Gateway
