#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule  Noizu.SimplePool.V2.ClusterManagement.HealthReport do
  @vsn 1.0
  @type t :: %__MODULE__{
               subject: any,
               summary: any,
               checks: Map.t,
               updated_on: DateTime.t,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    subject: nil,
    summary: :pending,
    checks: %{},
    updated_on: nil,
    meta: %{},
    vsn: @vsn
  ]

  def new(subject) do
    %__MODULE__{
      subject: subject
    }
  end

end