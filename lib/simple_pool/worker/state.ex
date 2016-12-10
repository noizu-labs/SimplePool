defmodule Noizu.SimplePool.Worker.State do
alias Noizu.SimplePool.Worker.State
  @type t :: %State{
    initialized: boolean, # Loading Initializetion should be done using Repos that adhere to a behavior.
    entity_ref: tuple,
    entity: any,
    extended: any
  }

  defstruct [
    initialized: false,
    entity_ref: nil,
    entity: nil,
    extended: nil
  ]
end
