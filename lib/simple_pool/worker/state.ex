defmodule Noizu.SimplePool.Worker.State do
alias Noizu.SimplePool.Worker.State
  @type t :: %State{
    initialized: boolean,
    migrating: boolean,
    worker_ref: tuple,
    inner_state: any,
    last_activity: any,
    extended: any
  }

  defstruct [
    initialized: false,
    migrating: false,
    worker_ref: nil,
    inner_state: nil,
    last_activity: nil,
    extended: %{}
  ]

  defimpl Inspect, for: Noizu.SimplePool.Worker.State do
    import Inspect.Algebra
    def inspect(entity, opts) do
      heading = "#Worker.State(#{inspect entity.worker_ref})"
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
