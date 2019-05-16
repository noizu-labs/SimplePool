#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration do
  alias Noizu.SimplePool.V2.MonitoringFramework.ServiceMonitorConfiguration

  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               master_node: atom,
               services: %{module => ServiceMonitorConfiguration.t},
               entry_point: {module, atom},
               vsn: any
             }

  defstruct [
    identifier: nil,
    master_node: :auto,
    services: %{},
    entry_point: nil,
    vsn: @vsn
  ]

  def new(identifier, master_node \\ :auto, services \\ %{}) do
    %__MODULE__{
      identifier: identifier,
      master_node: master_node,
      services: services,
    }
  end

  def add_service(%__MODULE__{} = this, service) do
    put_in(this, [Access.key(:services), service.pool], service)
  end

end
