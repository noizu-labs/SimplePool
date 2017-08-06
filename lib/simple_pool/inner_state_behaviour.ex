defmodule Noizu.SimplePool.InnerStateBehaviour do

  @callback init_hook() :: :nyi
  @callback terminate_hook() :: :nyi

  @callback shutdown() :: :nyi

  @callback call_forwarding(:info | :cast, this :: any, call :: any, envelope :: any) :: :nyi

  @callback fetch() :: :nyi
  @callback load() :: :nyi


end
