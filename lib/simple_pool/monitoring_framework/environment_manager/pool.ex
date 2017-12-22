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

    def init([sup, context] = args) do
      if verbose() do
        Logger.info(fn -> {base().banner("INIT #{__MODULE__} (#{inspect Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor}@#{inspect self()})"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
      end

      state = %State{
        pool: Noizu.MonitoringFramework.EnvironmentPool.WorkerSupervisor,
        server: Noizu.MonitoringFramework.EnvironmentPool.Server,
        status_details: :pending,
        extended: %{},
        options: option_settings(),
        entity: %{server: node(), effective: nil, default: nil, status: :offline}
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

    def entity_status(context, options \\ %{}) do
      timeout = options[:timeout] || 5_000
      try do
        GenServer.call(__MODULE__, {:m, {:status, options}, context}, timeout)
      catch
        :exit, e ->
          case e do
            {:timeout, c} -> {:timeout, c}
          end
      end # end try
    end


    def status_wait(target_state, context, timeout \\ :infinity)
    def status_wait(target_state, context, timeout) when is_atom(target_state) do
      status_wait(MapSet.new([target_state]), context, timeout)
    end

    def status_wait(target_state, context, timeout) when is_list(target_state) do
      status_wait(MapSet.new(target_state), context, timeout)
    end

    def status_wait(%MapSet{} = target_state, context, timeout) do
      if timeout == :infinity do
        case entity_status(context) do
          {:ack, state} -> if MapSet.member?(target_state, state), do: state, else: status_wait(target_state, context, timeout)
          _ -> status_wait(target_state, context, timeout)
        end
      else
        ts = :os.system_time(:millisecond)
        case entity_status(context, %{timeout: timeout}) do

          {:ack, state} ->
            if MapSet.member?(target_state, state) do
              state
            else
              t = timeout - (:os.system_time(:millisecond) - ts)
              if t > 0 do
                status_wait(target_state, context, t)
              else
                {:timeout, state}
              end
            end
          v ->
            t = timeout - (:os.system_time(:millisecond) - ts)
            if t > 0 do
              status_wait(target_state, context, t)
            else
              {:timeout, v}
            end
        end
      end
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

    def handle_call({:m, {:status, options}, context}, _from, state) do
      {:reply, {:ack, state.entity.status}, state}
    end

    def handle_cast({:m, {:start_services, options}, context}, state) do
      Noizu.SimplePool.Support.TestPool.PoolSupervisor.start_link(context)
      # 1. Pass in Definition
      # 2. Get HealthCheck
      state = state
              |> put_in([Access.key(:entity), :status], :online)
      {:noreply, state}
    end




  end # end defmodule GoldenRatio.Components.Gateway.Server
end # end defmodule GoldenRatio.Components.Gateway
