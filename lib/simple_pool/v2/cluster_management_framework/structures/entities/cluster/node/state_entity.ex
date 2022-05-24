#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateEntity do
  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: atom,
               status: atom,
               state: atom,
               pending_state: atom,
               node_definition: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Definition.t,
               status_details: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.Status.t,
               service_instances: Map.t,
               service_instances_statuses: Map.t,
               service_instances_health_reports: Map.t,
               health_report: Noizu.SimplePool.V2.ClusterManagement.HealthReport.t,
               updated_on: DateTime.t,
               state_changed_on: DateTime.t,
               pending_state_changed_on: DateTime.t,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    identifier: nil,
    status: nil,
    state: nil,
    node_definition: nil,
    status_details: nil,
    pending_state: nil,
    service_instances: %{},
    service_instances_statuses: %{},
    service_instances_health_reports: %{},
    health_report: :pending,
    updated_on: nil,
    state_changed_on: nil,
    pending_state_changed_on: nil,
    meta: %{},
    vsn: @vsn
  ]

  def reset(%__MODULE__{} = this, _context, options \\ %{}) do
    current_time = options[:current_time] || DateTime.utc_now()
    # @TODO flag service status entries as unknown/pending to force status updates.
    %__MODULE__{this|
      status: :warmup,
      state: :init,
      pending_state: :online,
      state_changed_on: current_time,
      pending_state_changed_on: current_time
    }
  end


  use Noizu.Scaffolding.V2.EntityBehaviour,
      sref_module: "node-state",
      entity_table:  Noizu.SimplePool.V2.Database.Cluster.Node.StateTable

  defimpl Noizu.ERP, for: Noizu.SimplePool.V2.ClusterManagement.Cluster.Node.StateEntity do
    defdelegate id(o), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate ref(o), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate sref(o), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate entity(o, options \\ nil), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate entity!(o, options \\ nil), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate record(o, options \\ nil), to: Noizu.Scaffolding.V2.ERPResolver
    defdelegate record!(o, options \\ nil), to: Noizu.Scaffolding.V2.ERPResolver

    def id_ok(o) do
      r = id(o)
      r && {:ok, r} || {:error, o}
    end
    def ref_ok(o) do
      r = ref(o)
      r && {:ok, r} || {:error, o}
    end
    def sref_ok(o) do
      r = sref(o)
      r && {:ok, r} || {:error, o}
    end
    def entity_ok(o, options \\ %{}) do
      r = entity(o, options)
      r && {:ok, r} || {:error, o}
    end
    def entity_ok!(o, options \\ %{}) do
      r = entity!(o, options)
      r && {:ok, r} || {:error, o}
    end
  end
end
