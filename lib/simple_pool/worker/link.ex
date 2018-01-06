#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.Worker.Link do

  @type t :: %__MODULE__{
    ref: any,
    handler: Module,
    handle: pid,
    expire: integer,
    update_after: integer | :infinity,
    state: :dead | :alive | {:error, any} | :invalid | :unknown
  }

  defstruct [
    ref: nil,
    handler: nil,
    handle: nil,
    expire: 0,
    update_after: 300, # Default recheck links after 5 minutes,  increase or reduce depending on how critical delivery of message is. or set to :infinity if other mechanism in place to update.
    state: :unknown
  ]


  defimpl Inspect, for: Noizu.SimplePool.Worker.Link do
    import Inspect.Algebra
    def inspect(entity, opts) do
      heading = "#Worker.Link(#{inspect entity.ref})"
      {seperator, end_seperator} = if opts.pretty, do: {"\n   ", "\n"}, else: {" ", " "}
      inner = cond do
        opts.limit == :infinity ->
          concat(["<#{seperator}", to_doc(Map.from_struct(entity), opts), "#{end_seperator}>"])
        opts.limit > 100 ->
          bare = %{handler: entity.handler, handle: entity.handle, expire: entity.expire, state: entity.state}
          concat(["<#{seperator}", to_doc(bare, opts), "#{end_seperator}>"])
        opts.limit > 10 ->
          bare = %{handler: entity.handler, state: entity.state}
          concat(["<#{seperator}", to_doc(bare, opts), "#{end_seperator}>"])
        true -> "<>"
      end
      concat [heading, inner]
    end # end inspect/2
  end # end defimpl
end
