defmodule Noizu.SimplePool.Server.ProviderBehaviour do

#-------------------------------------------------------------------------------
# GenServer Lifecycle
#-------------------------------------------------------------------------------
@callback init(pool_env :: any, settings :: any, sup, optional_arguments) ::  Noizu.SimplePool.Server.State.t
@callback terminate(reason :: any, state :: Noizu.SimplePool.Server.State.t) :: :ok

#-------------------------------------------------------------------------------
# Startup: Lazy Loading/Asynch Load/Immediate Load strategies. Blocking/Lazy Initialization, Loading Strategy.
#-------------------------------------------------------------------------------
@callback load(state :: Noizu.SimplePool.Server.State.t) :: :not_yet_defined # something like loaded, loading, ready, etc.
@callback status(state :: Noizu.SimplePool.Server.State.t) || :not_yet_defined # something like loading, loaded, ready, etc.

#-------------------------------------------------------------------------------
# Worker Process Management
# @TODO it is criticial to differentiate from on server process/off server process actions.
#       because we are passing state to all of these calls failing all else we can do a node() == state.node() comparison.
#-------------------------------------------------------------------------------
# (identifier :: any, sychronous :: boolean) :: :not_yet_defined # worker pid, success indifcator, worker ref, etc.
@callback worker_add!(ref/entity, initial\optional, context\optional)
@callback worker_remove!(ref/entity, context\optional)
@callback worker_register!(ref/entity, context\optional)
@callback worker_deregister!(ref/entity, context\optional)
@callback worker_migrate!(ref/entity, directions,  context\optional) # where direction qualifies where to load balance to, next available, specific, etc.
@callback worker_load!(ref/entity, initial\optional)

@callback worker_pid((ref/entity), :spawn!)
@callback worker_ref!(identifier) # conditionally setup ETS table if feature enabled and cache lookup results.

end
