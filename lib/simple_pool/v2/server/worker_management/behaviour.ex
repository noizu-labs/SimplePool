#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Server.WorkerManagement.Behaviour do
  #-------------------------------------------------------------------------------
  # GenServer Lifecycle
  #-------------------------------------------------------------------------------
  @callback init(module :: Module, sup :: any, context :: any, options :: Noizu.SimplePool.OptionSettings.t) :: any
  @callback terminate(server :: Module, reason :: any, state :: Noizu.SimplePool.Server.State.t, context :: any, options :: any) :: any

  #-------------------------------------------------------------------------------
  # Startup: Lazy Loading/Async Load/Immediate Load strategies. Blocking/Lazy Initialization, Loading Strategy.
  #-------------------------------------------------------------------------------
  @callback status(module :: Module, context :: any) :: any
  @callback load(module :: Module, context :: any, options :: any) :: any
  @callback load_complete(any, any, any) :: any

  #-------------------------------------------------------------------------------
  # Internal Routing
  #-------------------------------------------------------------------------------
  @callback i_call_handler(module :: Module, {:i, call :: any, context :: any}, from :: any, state :: Noizu.SimplePool.Server.State.t) :: {:reply, any, Noizu.SimplePool.Server.State.t}
  @callback i_cast_handler(module :: Module,{:i, call :: any, context :: any}, state :: Noizu.SimplePool.Server.State.t) :: {:noreply, Noizu.SimplePool.Server.State.t}
  @callback i_info_handler(module :: Module,{:i, call :: any, context :: any}, state :: Noizu.SimplePool.Server.State.t) :: {:noreply, Noizu.SimplePool.Server.State.t}

  #-------------------------------------------------------------------------------
  #
  #-------------------------------------------------------------------------------
  @callback s_call_handler(module :: Module,{:i, call :: any, context :: any}, from :: any, state :: Noizu.SimplePool.Server.State.t) :: {:reply, any, Noizu.SimplePool.Server.State.t}
  @callback s_cast_handler(module :: Module,{:i, call :: any, context :: any}, state :: Noizu.SimplePool.Server.State.t) :: {:noreply, Noizu.SimplePool.Server.State.t}
  @callback s_info_handler(module :: Module,{:i, call :: any, context :: any}, state :: Noizu.SimplePool.Server.State.t) :: {:noreply, Noizu.SimplePool.Server.State.t}

  #-------------------------------------------------------------------------------
  #
  #-------------------------------------------------------------------------------
  @callback m_call_handler(module :: Module,{:i, call :: any, context :: any}, from :: any, state :: Noizu.SimplePool.Server.State.t) :: {:reply, any, Noizu.SimplePool.Server.State.t}
  @callback m_cast_handler(module :: Module,{:i, call :: any, context :: any}, state :: Noizu.SimplePool.Server.State.t) :: {:noreply, Noizu.SimplePool.Server.State.t}
  @callback m_info_handler(module :: Module,{:i, call :: any, context :: any}, state :: Noizu.SimplePool.Server.State.t) :: {:noreply, Noizu.SimplePool.Server.State.t}

end
