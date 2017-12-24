#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.MonitoringFramework.Service.HealthCheck do
  alias Noizu.SimplePool.MonitoringFramework.Service.Definition

  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               process: pid,
               time_stamp: DateTime.t,
               status: :online | :degraded | :critical | :offline,
               directive: :free | :locked | :maintenance,
               definition: Definition.t,
               allocated: Map.t,
               health_index: float,
               events: [LifeCycleEvent.t],
               vsn: any
             }

  defstruct [
    identifier: nil,
    process: nil,
    time_stamp: nil,
    status: :offline,
    directive: :locked,
    definition: nil,
    allocated: nil,
    health_index: 0.0,
    events: [],
    vsn: @vsn
  ]


  defimpl Inspect, for: Noizu.SimplePool.MonitoringFramework.Service.HealthCheck do
    import Inspect.Algebra
    def inspect(entity, opts) do
      heading = "#Service.HealthCheck(#{inspect entity.identifier})"
      {seperator, end_seperator} = if opts.pretty, do: {"\n   ", "\n"}, else: {" ", " "}
      inner = cond do
        opts.limit == :infinity ->
          concat(["<#{seperator}", to_doc(Map.from_struct(entity), opts), "#{seperator}>"])
        opts.limit > 100 ->
          bare = %{status: entity.status, directive: entity.directive, allocated: entity.allocated, definition: entity.definition, health_index: entity.health_index}
          concat(["<#{seperator}", to_doc(bare, opts), "#{seperator}>"])
        true -> "<>"
      end
      concat [heading, inner]
    end # end inspect/2
  end # end defimpl

end