#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.WorkerLookupBehaviour do
  @type lock_response :: {:ack, record :: any} | {:nack, {details :: any, record :: any}} | {:nack, details :: any} | {:error, details :: any}

  @callback host!(ref :: tuple, server :: module, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: {:ok, atom} | {:spawn, atom} | {:error, details :: any} | {:restricted, atom}
  @callback record_event!(ref :: tuple, event :: atom, details :: any, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: any

  @callback register!(ref :: tuple, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: any
  @callback unregister!(ref :: tuple, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: any

  @callback process!(ref :: tuple, server :: module, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: lock_response
  @callback obtain_lock!(ref :: tuple, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: lock_response
  @callback release_lock!(ref :: tuple, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: lock_response
end