#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.MonitoringFramework.ServiceMonitorConfiguration do

  @vsn 1.0
  @type t :: %__MODULE__{
               pool: any,
               pool_settings: %{:server => Map.t, :worker => Map.t, :monitor => Map.t},
               hard_process_limit: integer,
               soft_process_limit: integer,
               process_target: integer,
               meta: Map.t,
               vsn: any
             }

  defstruct [
    pool: nil,
    pool_settings: %{server: %{}, worker: %{}, monitor: %{}},
    hard_process_limit: nil,
    soft_process_limit: nil,
    process_target: nil,
    meta: %{},
    vsn: @vsn
  ]


  @default_server_options %{}
  @default_worker_options %{}
  @default_monitor_options %{}

  def new(pool, hard_process_limit \\ 100_000, soft_process_limit \\ nil, process_target \\ nil, pool_settings \\ nil) do
    soft_process_limit = soft_process_limit || (2 * div(hard_process_limit, 3))
    process_target = process_target ||(2 * div(soft_process_limit, 3))
    pool_settings = (pool_settings || %{})
              |> update_in([:server], &(&1 || @default_server_options))
              |> update_in([:worker], &(&1 || @default_worker_options))
              |> update_in([:monitor], &(&1 || @default_monitor_options))
    meta = %{
      server: pool.pool_server(),
      supervisor: pool.pool_supervisor(),
      worker_supervisor: pool.pool_worker_supervisor(),
      worker: pool.pool_worker(),
    }

    %__MODULE__{
      pool: pool,
      pool_settings: pool_settings,
      hard_process_limit: hard_process_limit,
      soft_process_limit: soft_process_limit,
      process_target: process_target,
      meta: meta
    }
  end


end
