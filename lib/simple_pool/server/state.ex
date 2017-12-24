#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Server.State do
alias Noizu.SimplePool.Server.State

  @type t :: %State{
    pool: any,
    server: any,
    status_details: any,
    status: Map.t,
    extended: any,
    entity: any,
    options: Noizu.SimplePool.OptionSettings.t
  }

  defstruct [
    pool: nil,
    server: nil,
    status_details: nil,
    status: %{loading: :pending, state: :pending},
    extended: %{},
    entity: nil,
    options: nil
  ]

#-----------------------------------------------------------------------------
# Inspect Protocol
#-----------------------------------------------------------------------------
defimpl Inspect, for: Noizu.SimplePool.Server.State do
  import Inspect.Algebra
  def inspect(entity, opts) do
    heading = "#Server.State(#{inspect entity.server})"
    {seperator, end_seperator} = if opts.pretty, do: {"\n   ", "\n"}, else: {" ", " "}
    inner = cond do
      opts.limit == :infinity ->
        concat(["<#{seperator}", to_doc(Map.from_struct(entity), opts), "#{seperator}>"])
      true -> "<>"
    end
    concat [heading, inner]
  end # end inspect/2
end # end defimpl

end
