#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.Worker.HealthCheck do
  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               status: :online | :degraged | :critical | :offline,
               event_frequency: Map.t,
               check: float,
               events: list,
               vsn: any
             }

  defstruct [
    identifier: nil,
    status: :offline,
    event_frequency: %{},
    check: 0.0,
    events: [],
    vsn: @vsn
  ]



  defimpl Inspect, for: Noizu.SimplePool.Worker.HealthCheck do
    import Inspect.Algebra
    def inspect(entity, opts) do
      heading = "#Worker.HealthCheck(#{inspect entity.identifier})"
      {seperator, end_seperator} = if opts.pretty, do: {"\n   ", "\n"}, else: {" ", " "}
      inner = cond do
        opts.limit == :infinity ->
          concat(["<#{seperator}", to_doc(Map.from_struct(entity), opts), "#{end_seperator}>"])
        opts.limit > 100 ->
          bare = %{status: entity.status}
          concat(["<#{seperator}", to_doc(bare, opts), "#{end_seperator}>"])
        true -> "<>"
      end
      concat [heading, inner]
    end # end inspect/2
  end # end defimpl
end
