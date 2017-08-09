defmodule Noizu.SimplePool.InnerStateBehaviour do
  @callback terminate_hook(reason :: any, state :: any) :: :ok
  @callback shutdown(context :: any, state :: any) :: {:ok, state :: any} | {:wait, state :: any}
  @callback load(ref :: any) :: nil | any
  @callback load(ref :: any, context :: any) :: nil | any
  @callback load(ref :: any, options :: any, context :: any) :: nil | any
  @callback call_forwarding(call :: any, context :: any, state :: any) :: any
  @callback call_forwarding(call :: any, context :: any, from :: any, state :: any) :: any
  @callback fetch(options :: any, context :: any, state :: any) :: any
end
