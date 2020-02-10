#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor do
  @moduledoc """
  V2 Arch:

  Every node will have an ServerMonitor responsible for state on that node.
  The ServerMonitor will push/pull data to any other available monitors.
  It will keep the list available in a fg cache, and poll on init to find all available nodes that host a environment monitor service.

  Per node health information will be synced and stored in fast global caches on each monitor for determining host tenancy of new jobs.
  Event data will be persisted to local and distributed mnesia tables. (Core events will be persisted across cluster, other events will be persisted locally)
  Rate Limiters will apply to avoid flooding mnesia during a failure event. A simple ets counter may be used for this that is reset periodically.

  The ServerMonitor api surface as a rule will also be performed on the hosting node.
  A ClusterMonitorService will also be available for coordinating changes across the cluster.
  Rebalance/Migrate operations will belong to the ClusterMonitorService since they require cross node coordination.

  - Service PID Monitors
  - Node Up/Down Monitors
  - System Resource Monitors
  - Failure Rate Counters

  """

  @behaviour Noizu.SimplePool.V2.MonitoringFramework.MonitorBehaviour
  alias Noizu.ElixirCore.CallingContext
  alias Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration
  require Logger
  use Noizu.SimplePool.V2.StandAloneServiceBehaviour,
      default_modules: [:pool_supervisor, :monitor],
      worker_state_entity: nil,
      verbose: false

  #-----------------------------------
  #
  #-----------------------------------
  def reconfigure(%MonitorConfiguration{} = config, %CallingContext{} = context, opts \\ %{}) do
    server_system_call({:reconfigure, config, opts}, context, opts[:call])
  end

  #-----------------------------------
  #
  #-----------------------------------
  def bring_services_online(%CallingContext{} =  context, opts \\ %{}) do
    server_system_call({:bring_services_online, opts}, context, opts[:call])
  end

  #-----------------------------------
  #
  #-----------------------------------
  def status_wait(_target, %CallingContext{} = _context, _opts \\ %{}) do
    # @TODO implement
    Logger.error("#{__MODULE__}.status_wait NYI")
    :online
  end

  #-----------------------------------
  #
  #-----------------------------------
  defdelegate supports_service?(service, context, options), to: __MODULE__.Server
  defdelegate health_check(context, opts), to: __MODULE__.Server
  defdelegate lock_server(context, opts), to: __MODULE__.Server
  defdelegate release_server(context, opts), to: __MODULE__.Server
  defdelegate lock_services(services, context, options), to: __MODULE__.Server
  defdelegate release_services(services, context, options), to: __MODULE__.Server
  defdelegate select_host(ref, service, context, opts \\ %{}), to: __MODULE__.Server
  defdelegate record_server_event!(event, details, context, options), to: __MODULE__.Server

  defmodule Server do
    @vsn 1.0
    alias Noizu.SimplePool.V2.Server.State

    use Noizu.SimplePool.V2.ServerBehaviour,
        worker_state_entity: nil,
        server_monitor: Noizu.SimplePool.V2.MonitoringFramework.ServerMonitor
    require Logger

    def initial_state(args, _context) do
      Logger.error("@todo attempt to load configuration from persistence store - use indicator to detect version changes")
      configuration_id = args.definition || {:default, node()}

      monitor_configuration = %Noizu.SimplePool.V2.MonitoringFramework.MonitorConfiguration{
        identifier: configuration_id,
        master_node: :self,
        services: %{},
        entry_point: nil,
      }

      entity = %Noizu.SimplePool.V2.MonitoringFramework.MonitorState{
        identifier: configuration_id,
        configuration: monitor_configuration,
        services: %{},
        event_agent: nil, # @todo start agent.
      }

      %State{
        pool: pool(),
        entity: entity,
        status_details: :pending,
        extended: %{},
        environment_details: {:error, :nyi},
        options: option_settings()
      }
    end

    def reconfigure(state, config, _context, _opts) do
      # TODO - compare new configuration to existing configuration, update agent and service entries as appropriate.
      new_service_state = Enum.map(config.services, fn({_k,v}) ->
        {v.pool, %Noizu.SimplePool.V2.MonitoringFramework.ServiceState{pool: v.pool}}
      end) |> Map.new()
      state = state
              |> put_in([Access.key(:entity), Access.key(:configuration)], config)
              |> put_in([Access.key(:entity), Access.key(:services)], new_service_state)
      {:reply, state.entity, state}
    end

    def bring_services_online(state, context, _opts) do
      # @TODO async spawn, check existing state, setup service monitors that inform us if services fail.
      # @TODO start services from PoolSupervisor so that they are restarted automatically.
      # @TODO ability to specify sequence

      # Todo this should be nested under services not by itself in monitors.
      updated_services = Enum.reduce(state.entity.configuration.services, state.entity.services || %{},
        fn({_k, v}, acc) ->
          # todo pass in options v.pool_settings
          case pool_supervisor().add_child_supervisor(v.pool.pool_supervisor(), :auto, context) do
            {:ok, pid} ->
              put_in(acc, [v.pool], %{time: DateTime.utc_now(), error: nil, monitor: Process.monitor(pid), supervisor_process: pid})
            e ->
              Logger.error("Problem starting #{v.pool} - #{inspect e}")
              put_in(acc, [v.pool], %{time: DateTime.utc_now(), error: e, monitor: nil, supervisor_process: nil})
          end
        end
      )

      monitor_lookup = Enum.map(updated_services,  fn({k,v}) -> v.monitor && {v.monitor, k} end)
                       |> Enum.filter(&(&1 != nil))
                       |> Map.new()

      state = state
              |> put_in([Access.key(:entity), Access.key(:services)], updated_services)
              |> put_in([Access.key(:entity), Access.key(:meta), Access.key(:monitor_lookup)], monitor_lookup)

      IO.puts """
        =====================================
        updated_services: #{inspect updated_services, pretty: true, limit: :infinity}
        =====================================
      """

      {:reply, updated_services, state}
    end

    def process_service_down_event(reference, process, reason, state) do
      cond do
        state.entity == nil ->
          Logger.error "[ServiceDown] Unknown State.Entity."
          {:noreply, state}
        rl = state.entity.meta[:monitor_lookup][reference] ->
          Logger.error "[ServiceDown] Service Has Stopped #{rl}."
          {:noreply, state}
        true ->
          Logger.error "[ServiceDown] Unknown DownLink #{inspect {reference, process, reason}}."
          {:noreply, state}
      end
    end

    #------------------------------------------------------------------------
    # call router
    #------------------------------------------------------------------------
    def call_router_user(envelope, _from, state) do
      case envelope do
        {:m, {:reconfigure, config, opts}, context} -> reconfigure(state, config, context, opts)
        {:m, {:bring_services_online, opts}, context} -> bring_services_online(state, context, opts)
        _ -> nil
      end
    end

    #------------------------------------------------------------------------
    # info router
    #------------------------------------------------------------------------
    def info_router_user(envelope, state) do
      case envelope do
        {:DOWN, reference, :process, process, reason} -> process_service_down_event(reference, process, reason, state)
        _ -> nil
      end
    end




    def select_host(_ref, _service, _context, _opts \\ %{}) do
      # @TODO - To Optimize Host Selection,
      # 1. Load from FastGlobal instead of Amnesia.
      # 2. Instead of randomly selecting from hints use weight information and a dice roll to determine bucket.
      {:ack, node()}
    end

    def supports_service?(_service, _context, _options), do: :nyi
    def health_check(_context, _opts), do: :nyi
    def lock_server(_context, _opts), do: :nyi
    def release_server(_context, _opts), do: :nyi
    def lock_services(_services, _context, _opts), do: :nyi
    def release_services(_services, _context, _opts), do: :nyi

    @temporary_core_events MapSet.new([:start, :shutdown])
    def core_events() do
      # TODO use fast global wrapper around SettingTable
      @temporary_core_events
    end

    def record_server_event!(event, _details, _context, _opts) do
      if MapSet.member?(core_events(), event) do
        Logger.info(fn -> "TODO - write to ServerEventTable #{inspect event}" end)
      else
        Logger.info(fn -> "TODO - write to DetailedServerEventTable #{inspect event}" end)
      end
    end

  end # end defmodule Server
end
