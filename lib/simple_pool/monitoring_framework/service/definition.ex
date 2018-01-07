#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.MonitoringFramework.Service.Definition do
  @vsn 1.0
  @type t :: %__MODULE__{
               identifier: any,
               server: atom,
               pool: module,
               service: module,
               supervisor: module,
               server_options: any,
               worker_sup_options: any,
               time_stamp: DateTime.t,
               hard_limit: integer,
               soft_limit: integer,
               target: integer,
               vsn: any
             }

  defstruct [
    identifier: nil,
    server: nil,
    pool: nil,
    service: nil,
    supervisor: nil,
    server_options: nil,
    worker_sup_options: nil,
    time_stamp: nil,
    hard_limit: 0,
    soft_limit: 0,
    target: 0,
    vsn: @vsn
  ]

  defimpl Inspect, for: Noizu.SimplePool.MonitoringFramework.Service.Definition do
    import Inspect.Algebra
    def inspect(entity, opts) do
      heading = "#Service.Definition(#{inspect entity.identifier})"
      {seperator, end_seperator} = if opts.pretty, do: {"\n   ", "\n"}, else: {" ", " "}
      inner = cond do
        opts.limit == :infinity ->
          concat(["<#{seperator}", to_doc(Map.from_struct(entity), opts), "#{end_seperator}>"])
        opts.limit > 100 ->
          bare = %{hard_limit: entity.hard_limit, soft_limit: entity.soft_limit, target: entity.target}
          concat(["<#{seperator}", to_doc(bare, opts), "#{end_seperator}>"])
        true -> "<>"
      end
      concat [heading, inner]
    end # end inspect/2
  end # end defimpl
end

