defmodule Noizu.SimplePool.Server.State do
alias Noizu.SimplePool.Server.State

  @type t :: %State{
    pool: any,
    nmid_generator: {{integer, integer}, integer},
    status_details: any,
    status: atom,
    extended: any
  }

  defstruct [
    pool: nil,
    nmid_generator: nil,
    status_details: nil,
    status: nil,
    extended: nil
  ]

end
