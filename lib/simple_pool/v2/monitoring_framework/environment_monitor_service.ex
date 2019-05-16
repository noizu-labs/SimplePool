#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule Noizu.SimplePool.V2.MonitoringFramework.EnvironmentMonitorService do
  @behaviour Noizu.SimplePool.V2.MonitoringFramework.MonitorBehaviour
  alias Noizu.ElixirCore.CallingContext
  use Noizu.SimplePool.V2.StandAloneServiceBehaviour,
      default_modules: [:pool_supervisor, :monitor],
      worker_state_entity: nil,
      verbose: false

  def reconfigure(%Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration{} = config, %CallingContext{} = context, opts \\ %{}) do
    server_system_call({:reconfigure, config, opts}, context, opts[:call])
  end

  def bring_services_online(%CallingContext{} =  context, opts \\ %{}) do
    server_system_call({:bring_services_online, opts}, context, opts[:call])
  end

  def status_wait(target, %CallingContext{} = context, opts \\ %{}) do
    # @TODO implement
    :online
  end

  def reconfigure_remote(elixir_node, %Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration{} = config, %CallingContext{} = context, opts \\ %{}) do
    remote_server_system_call(node(),{:reconfigure, config, opts}, context, opts[:call])
  end

  def bring_services_online_remote(elixir_node, %CallingContext{} =  context, opts \\ %{}) do
    remote_server_system_call(node(),{:bring_services_online, opts}, context, opts[:call])
  end

  def status_wait_remote(elixir_node, target, %CallingContext{} = context, opts \\ %{}) do
    if (elixir_node == node()) do
      # @TODO implement
      :online
    else
      :rpc.call(elixir_node, __MODULE__, :status_wait, [target, context, opts], 600_000)
    end
  end


  defdelegate primary(), to: __MODULE__.Server
  defdelegate start_services(context, options), to: __MODULE__.Server
  defdelegate supports_service?(elixir_node, service, context, options), to: __MODULE__.Server
  defdelegate rebalance(source_nodes, target_nodes, services, context, options), to: __MODULE__.Server
  defdelegate offload(elixir_nodes, services, context, options), to: __MODULE__.Server
  defdelegate lock_services(elixir_nodes, services, context, options), to: __MODULE__.Server
  defdelegate release_services(elixir_nodes, services, context, options), to: __MODULE__.Server
  def select_host(ref, service, context, options) do
    # @todo incomplete logic
    {:ack, node()}
  end
  defdelegate record_server_event!(elixir_node, event, details, context, options), to: __MODULE__.Server
  defdelegate record_service_event!(elixir_node, service, event, details, context, options), to: __MODULE__.Server





  defmodule Server do
    @vsn 1.0
    alias Noizu.SimplePool.V2.Server.State

    use Noizu.SimplePool.V2.ServerBehaviour,
        worker_state_entity: nil,
        server_monitor: __MODULE__,
        worker_lookup_handler: Noizu.SimplePool.WorkerLookupBehaviour.Dynamic
    require Logger

    def initial_state(args, context) do
      # @todo attempt to load configuration from persistence store
      configuration_id = args.definition || {:default, node()}

      monitor_configuration = %Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration{
        identifier: configuration_id,
        master_node: :self,
        services: %{},
        entry_point: nil,
      }

      entity = %Noizu.SimplePool.V2.MonitoringFramework.MonitorState{
        identifier: configuration_id,
        configuration: monitor_configuration,
        services: %{},
        event_agent: nil, # @todo start agent.
      }

      %State{
        pool: pool(),
        entity: entity,
        status_details: :pending,
        extended: %{},
        environment_details: {:error, :nyi},
        options: option_settings()
      }
    end

    def reconfigure(state, config, context, opts) do
      # TODO - compare new configuration to existing configuration, update agent and service entries as appropriate.
      new_service_state = Enum.map(config.services, fn({k,v}) ->
        {v.pool, %Noizu.SimplePool.V2.MonitoringFramework.ServiceState{pool: v.pool}}
      end) |> Map.new()
      state = state
              |> put_in([Access.key(:entity), Access.key(:configuration)], config)
              |> put_in([Access.key(:entity), Access.key(:services)], new_service_state)
      {:reply, state.entity, state}
    end

    def bring_services_online(state, context, opts) do
      # @TODO async spawn, check existing state, setup service monitors that inform us if services fail.
      # @TODO start services from PoolSupervisor so that they are restarted automatically.
      # @TODO ability to specify sequence

      # Todo this should be nested under services not by itself in monitors.
      updated_services = Enum.reduce(state.entity.configuration.services, state.entity.services || %{},
        fn({_k, v}, acc) ->
          # todo pass in options v.pool_settings
          case pool_supervisor().add_child_supervisor(v.pool.pool_supervisor(), :auto, context) do
            {:ok, pid} ->
              put_in(acc, [v.pool], %{time: DateTime.utc_now(), error: nil, monitor: Process.monitor(pid), supervisor_process: pid})
            e ->
              Logger.error("Problem starting #{v.pool} - #{inspect e}")
              put_in(acc, [v.pool], %{time: DateTime.utc_now(), error: e, monitor: nil, supervisor_process: nil})
          end
        end
      )

      monitor_lookup = Enum.map(updated_services,  fn({k,v}) -> v.monitor && {v.monitor, k} end)
                       |> Enum.filter(&(&1 != nil))
                       |> Map.new()

      state = state
              |> put_in([Access.key(:entity), Access.key(:services)], updated_services)
              |> put_in([Access.key(:entity), Access.key(:meta), Access.key(:monitor_lookup)], monitor_lookup)

      IO.puts """
        =====================================
        updated_services: #{inspect updated_services, pretty: true, limit: :infinity}
        =====================================
      """

      {:reply, updated_services, state}
    end

    def process_service_down_event(reference, process, reason, state) do
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
    def call_router_user(envelope, from, state) do
      case envelope do
        {:m, {:reconfigure, config, opts}, context} -> reconfigure(state, config, context, opts)
        {:m, {:bring_services_online, opts}, context} -> bring_services_online(state, context, opts)
        _ -> nil
      end
    end



    #------------------------------------------------------------------------
    # info router
    #------------------------------------------------------------------------
    def info_router_user(envelope, state) do
      case envelope do
        {:DOWN, reference, :process, process, reason} -> process_service_down_event(reference, process, reason, state)
        _ -> nil
      end
    end













    def primary(), do: throw :wip
    def start_services(context, options), do: throw :wip
    def supports_service?(elixir_node, service, context, options), do: throw :wip
    def rebalance(source_nodes, target_nodes, services, context, options), do: throw :wip
    def offload(elixir_nodes, services, context, options), do: throw :wip
    def lock_services(elixir_nodes, services, context, options), do: throw :wip
    def release_services(elixir_nodes, services, context, options), do: throw :wip
    def select_host(ref, service, context, options), do: throw :wip
    def record_server_event!(elixir_node, event, details, context, options), do: throw :wip
    def record_service_event!(elixir_node, service, event, details, context, options), do: throw :wip




    #def fetch_internal_state(server, context, options)
    #def fetch_internal_state(context, options)

    #def set_internal_state(server, state, context, options)
    #def set_internal_state(state, context, options)



    #def server_bulk_migrate!(services, context, options)
    #def total_unallocated(unallocated)
    #def fill_to({unallocated, service_allocation}, level, output_server_list, service_list, per_server_targets)

    #def lock_server(context), do: lock_servers([node()], :all, context, %{})
    #def lock_server(context, options), do: lock_servers([node()], :all, context, options)
    #def lock_server(components, context, options), do: lock_servers([node()], components, context, options)
    #def lock_server(server, components, context, options), do: lock_servers([server], components, context, options)
    #def lock_servers(servers, components, context, options \\ %{})

    #def release_server(context), do: release_servers([node()], :all, context, %{})
    #def release_server(context, options), do: release_servers([node()], :all, context, options)
    #def release_server(components, context, options), do: release_servers([node()], components, context, options)
    #def release_server(server, components, context, options), do: release_servers([server], components, context, options)

    #def release_servers(servers, components, context, options \\ %{})
    #def select_host(_ref, component, _context, options \\ %{})
    #def record_server_event!(server, event, details, _context, options \\ %{})
    #def record_service_event!(server, service, event, details, _context, options \\ %{})

    #def handle_info({:DOWN, ref, :process, _process, _msg} = event, state)
    #def init([_sup, definition, context] = _args)
    #---------------------------------------------------------------------------
    # Convenience Methods
    #---------------------------------------------------------------------------
    #def register(initial, context, options \\ %{})
    #def start_services(context, options \\ %{})
    #def update_hints!(context, options \\ %{})
    #def internal_update_hints(components, context, options \\ %{})

    #---------------------------------------------------------------------------
    # Handlers
    #---------------------------------------------------------------------------
    #def perform_join(state, server, {pid, _ref}, initial, _context, options)
    #def update_effective(state, context, options)
    #def server_health_check!(server, context, options)
    #def server_health_check!(context, options)
    #def node_health_check!(context, options)
    #def perform_hint_update(state, components, context, options)




  end # end defmodule Server

end