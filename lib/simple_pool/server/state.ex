defmodule Noizu.SimplePool.Server.State do
alias Noizu.SimplePool.Server.State

  @type t :: %State{
    pool: any,
    server: any,
    status_details: any,
    status: Map.t,
    extended: any,
    options: Noizu.SimplePool.OptionSettings.t
  }

  defstruct [
    pool: nil,
    server: nil,
    status_details: nil,
    status: %{loading: :pending, state: :pending},
    extended: %{},
    options: nil
  ]

end
