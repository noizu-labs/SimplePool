#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule Noizu.SimplePool.V2.MonitoringFramework.EnvironmentMonitorService do
  @behaviour Noizu.SimplePool.V2.MonitoringFramework.MonitorBehaviour

  use Noizu.SimplePool.V2.StandAloneServiceBehaviour,
      default_modules: [:pool_supervisor, :monitor],
      worker_state_entity: nil,
      verbose: false

  defmodule Server do
    @vsn 1.0
    use Noizu.SimplePool.V2.ServerBehaviour,
        worker_state_entity: nil,
        server_monitor: __MODULE__,
        worker_lookup_handler: Noizu.SimplePool.WorkerLookupBehaviour.Dynamic

    @behaviour Noizu.SimplePool.V2.MonitoringFramework.MonitorBehaviour

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