defmodule Noizu.SimplePool.Worker.State do
alias Noizu.SimplePool.Worker.State
  @type t :: %State{
    initialized: boolean,
    worker_ref: tuple,
    inner_state: any,
    last_activity: any,
    extended: any
  }

  defstruct [
    initialized: false,
    worker_ref: nil,
    inner_state: nil,
    last_activity: nil,
    extended: nil
  ]
end
