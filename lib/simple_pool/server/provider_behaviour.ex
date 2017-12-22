#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Server.ProviderBehaviour do

  #-------------------------------------------------------------------------------
  # GenServer Lifecycle
  #-------------------------------------------------------------------------------
  @callback init(module :: Module, sup :: any, options :: Noizu.SimplePool.OptionSettings.t, any) :: any
  @callback terminate(reason :: any, state :: Noizu.SimplePool.Server.State.t) :: any

  #-------------------------------------------------------------------------------
  # Startup: Lazy Loading/Async Load/Immediate Load strategies. Blocking/Lazy Initialization, Loading Strategy.
  #-------------------------------------------------------------------------------
  @callback status(module :: Module, context :: any) :: any
  @callback load(module :: Module, settings :: any, context :: any) :: any
  @callback load_complete(any, any, any) :: any

  #-------------------------------------------------------------------------------
  # Internal Routing
  #-------------------------------------------------------------------------------
  @callback internal_call_handler({:i, call :: any, context :: any}, from :: any, state :: Noizu.SimplePool.Server.State.t) :: {:reply, any, Noizu.SimplePool.Server.State.t}
  @callback internal_cast_handler({:i, call :: any, context :: any}, state :: Noizu.SimplePool.Server.State.t) :: {:noreply, Noizu.SimplePool.Server.State.t}
  @callback internal_info_handler({:i, call :: any, context :: any}, state :: Noizu.SimplePool.Server.State.t) :: {:noreply, Noizu.SimplePool.Server.State.t}
end
