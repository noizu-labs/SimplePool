#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.MonitoringFramework.EnvironmentPool do
  #alias Noizu.Scaffolding.CallingContext
  use Noizu.SimplePool.Behaviour,
      default_modules: [:pool_supervisor, :worker_supervisor],
      worker_state_entity: Noizu.MonitoringFramework.EnvironmentWorkerEntity,
      verbose: false

  defmodule Worker do
    @vsn 1.0
    use Noizu.SimplePool.WorkerBehaviour,
        worker_state_entity: Noizu.MonitoringFramework.EnvironmentWorkerEntity,
        verbose: false
    require Logger
  end # end worker

  #=============================================================================
  # @Server
  #=============================================================================
  defmodule Server do
    @vsn 1.0
    use Noizu.SimplePool.ServerBehaviour,
        worker_state_entity: Noizu.MonitoringFramework.EnvironmentWorkerEntity,
        override: [:init]

    alias Noizu.SimplePool.Server.State

    def init([sup, context, definition] = args) do
      if verbose() do
        Logger.info(fn -> {base().banner("INIT #{__MODULE__} (#{inspect Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor}@#{inspect self()})"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
      end

      state = %State{
        pool: Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor,
        server: Noizu.MonitoringFramework.EnvironmentPool.Server,
        status_details: :pending,
        extended: %{},
        options: option_settings(),
        entity: %{server: node(), definition: definition, effective: nil, default: nil, status: :offline}
      }
      {:ok, state}
    end

    #---------------------------------------------------------------------------
    # Convenience Methods
    #---------------------------------------------------------------------------

    def register(initial, context, options \\ %{}) do
      GenServer.call(__MODULE__, {:m, {:register, initial, options}, context}, 30_000)
    end

    def start_services(context, options \\ %{}) do
      GenServer.cast(__MODULE__, {:m, {:start_services, options}, context})
    end


    #---------------------------------------------------------------------------
    # Handlers
    #---------------------------------------------------------------------------
    def handle_call({:m, {:register, initial, options}, context}, _from, state) do
      state = state
              |> put_in([Access.key(:entity), :effective], initial)
              |> put_in([Access.key(:entity), :default], initial)
              |> put_in([Access.key(:entity), :status], :registered)
      {:reply, state.entity.effective, state}
    end

    def handle_cast({:m, {:start_services, options}, context}, state) do

      # @TODO async task, current status check (check service)
      # @TODO pass in definition/healthcheck
      # @TODO retrieve status/wait on status. callback loop.
      Enum.reduce(state.entity.effective.services, :ok, fn({k,v}, acc) ->
        v.definition.supervisor.start_link(context, v.definition)
      end)

      # @TODO Grab Status, update defintions.
      tasks = Enum.reduce(state.entity.effective.services, [], fn({k,v}, acc) ->
        acc ++ [Task.async( fn ->
          Process.sleep(2_000)
          {k,v} end)] # TODO health_check call
      end)

      effective = Enum.reduce(tasks, state.entity.effective, fn(t, acc) ->
        {k, v} = Task.await(t)
        put_in(acc, [Access.key(:services), k], v)
      end)
      state = state
              |> put_in([Access.key(:entity), :effective], effective)
              |> put_in([Access.key(:entity), :status], :online)

      Process.sleep(5_000)

      {:noreply, state}
    end




  end # end defmodule GoldenRatio.Components.Gateway.Server
end # end defmodule GoldenRatio.Components.Gateway
