#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Server.State do
  alias Noizu.SimplePool.V2.Server.State

  @type t :: %State{
               worker_supervisor: any, # deprecated
               service: any, # deprecated
               pool: any,
               status_details: any,
               status: Map.t,
               extended: any,
               entity: any,
               environment_details: Noizu.SimplePool.Server.EnvironmentDetails.t,
               options: Noizu.SimplePool.OptionSettings.t,
               meta: Map.t,
             }

  defstruct [
    worker_supervisor: nil, # deprecated
    service: nil, # deprecated

    pool: nil,
    status_details: nil,
    status: %{loading: :pending, state: :pending},
    extended: %{},
    entity: nil,
    environment_details: nil,
    options: nil,
    meta: %{},
  ]

  #-----------------------------------------------------------------------------
  # Inspect Protocol
  #-----------------------------------------------------------------------------
  defimpl Inspect, for: Noizu.SimplePool.V2.Server.State do
    import Inspect.Algebra
    def inspect(entity, opts) do
      heading = "#Server.State(#{inspect entity.service})"
      {seperator, end_seperator} = if opts.pretty, do: {"\n   ", "\n"}, else: {" ", " "}
      inner = cond do
        opts.limit == :infinity ->
          concat(["<#{seperator}", to_doc(Map.from_struct(entity), opts), "#{end_seperator}>"])
        true -> "<>"
      end
      concat [heading, inner]
    end # end inspect/2
  end # end defimpl

end
