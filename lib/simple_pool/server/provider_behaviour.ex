defmodule Noizu.SimplePool.Server.ProviderBehaviour do

  #-------------------------------------------------------------------------------
  # GenServer Lifecycle
  #-------------------------------------------------------------------------------
  @callback init(module :: Module, sup :: any, options :: Noizu.SimplePool.OptionSettings.t) :: any
  @callback terminate(reason :: any, state :: Noizu.SimplePool.Server.State.t) :: any

  #-------------------------------------------------------------------------------
  # Startup: Lazy Loading/Asynch Load/Immediate Load strategies. Blocking/Lazy Initialization, Loading Strategy.
  #-------------------------------------------------------------------------------
  @callback status(module :: Module, context :: any) :: any
  @callback load(module :: Module, settings :: any, context :: any) :: any

  #-------------------------------------------------------------------------------
  # Worker Process Management
  #-------------------------------------------------------------------------------
  #@callback worker_add!(module :: Module, ref :: any, options :: any, context :: any) :: any
  #@callback worker_remove!(module :: Module, ref :: any, options :: any, context :: any) :: any
  #@callback worker_migrate!(module :: Module, ref :: any, rebase :: any, options :: any, context :: any) :: any
  #@callback worker_load!(module :: Module, ref :: any, options :: any, context :: any) :: any
  #@callback worker_register!(module :: Module, ref :: any, context :: any) :: any
  #@callback worker_deregister!(module :: Module, ref :: any, context :: any) :: any
  #@callback worker_clear!(module :: Module, ref :: any, process_node :: any, context :: any) :: any
  #@callback worker_pid!(module :: Module, ref :: any, options :: any, context :: any) :: any
  #@callback worker_ref!(module :: Module, identifier :: any, context :: any) :: any

  #-------------------------------------------------------------------------------
  # Internal Routing
  #-------------------------------------------------------------------------------
  @callback internal_call_handler({:i, call :: any, context :: any}, from :: any, state :: Noizu.SimplePool.Server.State.t) :: {:reply, any, Noizu.SimplePool.Server.State.t}
  @callback internal_cast_handler({:i, call :: any, context :: any}, state :: Noizu.SimplePool.Server.State.t) :: {:noreply, Noizu.SimplePool.Server.State.t}
  @callback internal_info_handler({:i, call :: any, context :: any}, state :: Noizu.SimplePool.Server.State.t) :: {:noreply, Noizu.SimplePool.Server.State.t}
end
