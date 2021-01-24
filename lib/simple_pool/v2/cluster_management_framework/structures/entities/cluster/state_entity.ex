#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity do
  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: atom,
               node: atom,
               process: pid,
               status: atom,
               state: atom,
               pending_state: atom,
               cluster_definition: Noizu.SimplePool.V2.ClusterManagement.Cluster.Definition.t,
               service_definitions: Map.t,
               service_statuses: Map.t,
               status_details: Map.t,
               health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.t,
               updated_on: DateTime.t,
               telemetry_handler: any,
               event_handler: any,
               state_changed_on: DateTime.t,
               pending_state_changed_on: DateTime.t,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    identifier: nil,
    node: nil,
    process: nil,
    status: :unknown,
    state: :offline,
    pending_state: :offline,
    cluster_definition: nil,
    service_definitions: %{},
    service_statuses: %{},
    status_details: %{},
    health_report: :pending,
    updated_on: nil,
    telemetry_handler: nil,
    event_handler: nil,
    state_changed_on: nil,
    pending_state_changed_on: nil,
    meta: %{},
    vsn: @vsn
  ]

  def reset(%__MODULE__{} = this, _context, options \\ %{}) do
    # Todo flag statuses as pending
    current_time = options[:current_time] || DateTime.utc_now()
    %__MODULE__{this|
      node: options[:node] || node(),
      process: options[:pid] || self(),
      status: :warmup,
      state: :init,
      pending_state: :online,
      state_changed_on: current_time,
      pending_state_changed_on: current_time,
      #state_changed_on: DateTime.utc_now(),
      #pending_state_changed_on: DateTime.utc_now()
    }
  end

  use Noizu.Scaffolding.V2.EntityBehaviour,
      sref_module: "cluster-state",
      entity_table:  Noizu.SimplePool.V2.Database.Cluster.StateTable

  defimpl Noizu.ERP, for: Noizu.SimplePool.V2.ClusterManagement.Cluster.StateEntity do
    defdelegate id(o), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate ref(o), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate sref(o), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate entity(o, options \\ nil), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate entity!(o, options \\ nil), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate record(o, options \\ nil), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate record!(o, options \\ nil), to: Noizu.Scaffolding.V2.ERPResolver
  end
end
