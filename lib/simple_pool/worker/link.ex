defmodule  Noizu.SimplePool.Worker.Link do

  @type t :: %__MODULE__{
    ref: any,
    handler: Module,
    handle: pid,
    state: :dead | :alive | {:error, any} | :invalid | :unknown
  }

  defstruct [
    ref: nil,
    handler: nil,
    handle: nil,
    state: :unknown
  ]
end
