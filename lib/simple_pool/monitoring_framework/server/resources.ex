#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.MonitoringFramework.Server.Resources do

  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               time_stamp: DateTime.t,
               cpu: %{nproc: integer, load: %{1 => float, 5 => float, 15 => float, 30 => float}},
               ram: %{total: float, allocated: float},
               vsn: any
             }

  defstruct [
    identifier: nil,
    time_stamp: nil,
    cpu: %{nproc: 0, load: %{1 => 0.0, 5 => 0.0, 15 => 0.0, 30 => 0.0}},
    ram: %{total: 0.0, allocated: 0.0},
    vsn: @vsn
  ]

  defimpl Inspect, for: Noizu.SimplePool.MonitoringFramework.Server.Resources do
    import Inspect.Algebra
    def inspect(entity, opts) do
      heading = "#Server.Resources(#{inspect entity.identifier})"
      {seperator, end_seperator} = if opts.pretty, do: {"\n   ", "\n"}, else: {" ", " "}
      inner = cond do
        opts.limit == :infinity ->
          concat(["<#{seperator}", to_doc(Map.from_struct(entity), opts), "#{end_seperator}>"])
        opts.limit > 100 ->
          bare = %{time_stamp: entity.time_stamp, cpu: entity.cpu, ram: entity.ram}
          concat(["<#{seperator}", to_doc(bare, opts), "#{end_seperator}>"])
        true -> "<>"
      end
      concat [heading, inner]
    end # end inspect/2
  end # end defimpl

end
