#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerManagement.WorkerManagementProvider do
  require Logger

  @doc """
  Count children of all worker supervisors.
  """
  def count_supervisor_children(pool_server), do: pool_server.pool_worker_supervisor().count_children()

  @doc """
  Group supervisor children by user provided method.
  """
  def group_supervisor_children(pool_server, group_fn), do: pool_server.pool_worker_supervisor().group_children(group_fn)

  @doc """
   Get number of active worker supervisors.
  """
  def active_supervisors(pool_server), do: pool_server.pool_worker_supervisor().active_supervisors()

  @doc """
   Get a supervisor module by index position.
  """
  def supervisor_by_index(pool_server, index), do:  pool_server.pool_worker_supervisor().supervisor_by_index(index)

  @doc """
    Return list of available worker supervisors.
  """
  def available_supervisors(pool_server), do: pool_server.pool_worker_supervisor().available_supervisors()

  @doc """
   Return supervisor responsible for a specific worker.
  """
  def current_supervisor(pool_server, ref), do: pool_server.pool_worker_supervisor().current_supervisors(ref)

  @doc """

  @note was worker_sup_start
  """
  def worker_start(pool_server, ref, transfer_state, context), do: pool_server.pool_worker_supervisor().worker_start(ref, transfer_state, context)

  @doc """

  @note was worker_sup_start
  """
  def worker_start(pool_server, ref, context), do: pool_server.pool_worker_supervisor().worker_start(ref, context)

  @doc """

  @note was worker_sup_terminate
  """
  def worker_terminate(pool_server, ref, context, options \\ %{}), do: pool_server.pool_worker_supervisor().worker_terminate(ref, context, options)

  @doc """

  @note was worker_sup_remove
  """
  def worker_remove(pool_server, ref, context, options \\ %{}), do: pool_server.pool_worker_supervisor().worker_remove(ref, context, options)

  def worker_add!(pool_server, ref, context \\ nil, options \\ %{}), do: pool_server.pool_worker_supervisor().worker_add!(ref, context || Noizu.ElixirCore.CallingContext.system(), options)

  @doc """

  """
  def bulk_migrate!(_pool_server, _transfer_server, _context, _options), do: throw :pri0_bulk_migrate!

  @doc """

  """
  def migrate!(pool_server, ref, rebase, context \\ nil, options \\ %{}) do
    context = context || Noizu.ElixirCore.CallingContext.system()
    if options[:sync] do
      pool_server.router().s_call!(ref, {:migrate!, ref, rebase, options}, context, options, options[:timeout] || 60_000)
    else
      pool_server.router().s_cast!(ref, {:migrate!, ref, rebase, options}, context)
    end
  end

  @doc """

  """
  def worker_load!(pool_server, ref, context \\ nil, options \\ %{}), do: pool_server.router().s_cast!(ref, {:load, options}, context ||  Noizu.ElixirCore.CallingContext.system())

  @doc """

  """
  def worker_ref!(pool_server, identifier, _context \\ nil), do: pool_server.pool_worker_state_entity().ref(identifier)

  @doc """

  """
  def terminate!(pool_server, ref, context, options) do
    pool_server.router().run_on_host(ref, {pool_server.worker_management(), :r_terminate!, [ref, context, options]}, context, options)
  end

  def r_terminate!(pool_server, ref, context, options) do
    options_b = put_in(options, [:lock], %{type: :reap, for: 60})
    case pool_server.worker_management().obtain_lock!(ref, context, options_b) do
      {:ack, _lock} -> pool_server.worker_management().worker_terminate(ref, context, options_b)
      o -> o
    end
  end


  @doc """

  """
  def remove!(pool_server, ref, context, options) do
    pool_server.router().run_on_host(ref, {pool_server.worker_management(), :r_remove!, [ref, context, options]}, context, options)
  end

  def r_remove!(pool_server, ref, context, options) do
    options_b = put_in(options, [:lock], %{type: :reap, for: 60})
    case pool_server.worker_management().obtain_lock!(ref, context, options_b) do
      {:ack, _lock} -> pool_server.worker_management().worker_remove(ref, context, options_b)
      o -> o
    end
  end

  @doc """

  """
  def accept_transfer!(pool_server, ref, state, context \\ nil, options \\ %{}) do
    options_b = options
                |> put_in([:lock], %{type: :transfer})
    case pool_server.worker_management().obtain_lock!(ref, context, options_b) do
      {:ack, _lock} ->
        case pool_server.worker_management().worker_start(ref, state, context) do
          {:ack, pid} ->
            {:ack, pid}
          o -> {:error, {:worker_start, o}}
        end
      o -> {:error, {:get_lock, o}}
    end
  end

  @doc """

  """
  def lock!(pool_server, context, options \\ %{}), do: pool_server.router().internal_system_call({:lock!, options}, context, options)

  @doc """

  """
  def release!(pool_server, context, options \\ %{}), do: pool_server.router().internal_system_call({:release!, options}, context, options)

  # @todo we should tweak function signatures for workers! method.
  @doc """

  """
  def workers!(pool_server, %Noizu.ElixirCore.CallingContext{} = context), do: workers!(pool_server, node(), pool_server.pool_worker_entity().__struct__, context, %{})

  def workers!(pool_server, %Noizu.ElixirCore.CallingContext{} = context, options), do: workers!(pool_server, node(), pool_server.pool_worker_entity().__struct__, context, options)

  def workers!(pool_server, host, %Noizu.ElixirCore.CallingContext{} = context), do: workers!(pool_server, host, pool_server.pool_worker_entity().__struct__, context, %{})

  def workers!(pool_server, host, %Noizu.ElixirCore.CallingContext{} = context, options), do: workers!(pool_server, host, pool_server.pool_worker_entity().__struct__, context, options)

  def workers!(pool_server, host, service_entity, %Noizu.ElixirCore.CallingContext{} = context), do: workers!(pool_server, host, service_entity, context, %{})

  def workers!(pool_server, host, service_entity, %Noizu.ElixirCore.CallingContext{} = context, options) do
    Logger.warn("[V2] New workers!() Implementation Needed")
    pool_server.worker_lookup_deprecated().workers!(host, service_entity, context, options)
  end


  @doc """

  """
  def host!(pool_server, ref, context, options \\ %{spawn: true}) do
    Logger.warn("[V2] New host!() Implementation Needed")
    pool_server.worker_lookup_deprecated().host!(ref, pool_server, context, options) |> IO.inspect
  end

  @doc """

  """
  def record_event!(pool_server, ref, event, details, context, options \\ %{}) do
    Logger.warn("[V2] New record_event!() Implementation Needed")
    pool_server.worker_lookup_deprecated().record_event!(ref, event, details, context, options)
  end

  @doc """

  """
  def events!(pool_server, ref, context, options \\ %{}) do
    Logger.warn("[V2] New events!() Implementation Needed")
    pool_server.worker_lookup_deprecated().events!(ref, context, options)
  end

  @doc """

  """
  def set_node!(pool_server, ref, context, options \\ %{}) do
    Logger.warn("[V2] New set_node!() Implementation Needed")
    pool_server.worker_lookup_deprecated().set_node!(ref, context, options)
  end

  @doc """

  """
  def register!(pool_server, ref, context, options \\ %{}) do
    Logger.warn("[V2] New register!() Implementation Needed")
    pool_server.worker_lookup_deprecated().register!(ref, context, options)
  end

  @doc """

  """
  def unregister!(pool_server, ref, context, options \\ %{}) do
    Logger.warn("[V2] New unregister!() Implementation Needed")
    pool_server.worker_lookup_deprecated().unregister!(ref, context, options)
  end

  @doc """

  """
  def obtain_lock!(pool_server, ref, context, options \\ %{}) do
    Logger.warn("[V2] New obtain_lock!() Implementation Needed")
    pool_server.worker_lookup_deprecated().obtain_lock!(ref, context, options)
  end

  @doc """

  """
  def release_lock!(pool_server, ref, context, options \\ %{}) do
    Logger.warn("[V2] New release_lock!() Implementation Needed")
    pool_server.worker_lookup_deprecated().release_lock!(ref, context, options)
  end

  @doc """

  """
  def process!(pool_server, ref, context, options \\ %{}) do
    Logger.warn("[V2] New process!() Implementation Needed")
    pool_server.worker_lookup_deprecated().process!(ref, pool_server.pool(), pool_server, context, options) |> IO.inspect
  end

end