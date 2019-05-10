#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.ServiceManagement.ServiceManagementProvider do
  alias Noizu.SimplePool.Server.State, as: ServerState
  require Logger

  @doc """

  """
  def default_definition(pool_server) do
    pool_server.meta()[:default_definition]
    |> put_in([Access.key(:time_stamp)], DateTime.utc_now())
  end

  @doc """

  """
  def enable_server!(_pool_server, _node), do: :pending # Not implemented for V1 either

  @doc """

  """
  def disable_server!(_pool_server, _node), do: :pending # Not implemented for V1 either

  @doc """

  """
  def status(pool_server, context \\ nil), do: pool_server.router().internal_call(:status, context)

  @doc """

  """
  def load(pool_server, context \\ nil, options \\ nil), do: pool_server.router().internal_system_call({:load, options}, context)

  @doc """

  """
  def load_complete(%ServerState{} = this, _process, _context) do
    this
    |> put_in([Access.key(:status), Access.key(:loading)], :complete)
    |> put_in([Access.key(:status), Access.key(:state)], :ready)
    |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:status)], :online)
    |> put_in([Access.key(:environment_details), Access.key(:effective), Access.key(:directive)], :online)
    |> put_in([Access.key(:extended), Access.key(:load_process)], nil)
  end

  @doc """

  """
  def status_wait(pool_server, target_state, context, timeout \\ :infinity)
  def status_wait(pool_server, target_state, context, timeout) when is_atom(target_state) do
    status_wait(pool_server, MapSet.new([target_state]), context, timeout)
  end

  def status_wait(pool_server, target_state, context, timeout) when is_list(target_state) do
    status_wait(pool_server, MapSet.new(target_state), context, timeout)
  end

  def status_wait(pool_server, %MapSet{} = target_state, context, timeout) do
    if timeout == :infinity do
      case pool_server.service_management().entity_status(context) do
        {:ack, state} -> if MapSet.member?(target_state, state), do: state, else: status_wait(pool_server, target_state, context, timeout)
        _ -> status_wait(pool_server, target_state, context, timeout)
      end
    else
      ts = :os.system_time(:millisecond)
      case pool_server.service_management().entity_status(context, %{timeout: timeout}) do
        {:ack, state} ->
          if MapSet.member?(target_state, state) do
            state
          else
            t = timeout - (:os.system_time(:millisecond) - ts)
            if t > 0 do
              status_wait(pool_server, target_state, context, t)
            else
              {:timeout, state}
            end
          end
        v ->
          t = timeout - (:os.system_time(:millisecond) - ts)
          if t > 0 do
            status_wait(pool_server, target_state, context, t)
          else
            {:timeout, v}
          end
      end
    end
  end









  @doc """

  """
  def entity_status(pool_server, context, options \\ %{}) do
    try do
      pool_server.router().internal_system_call({:status, options}, context, options)
    catch
      :rescue, e ->
        case e do
          {:timeout, c} -> {:timeout, c}
          _ -> {:error, {:rescue, e}}
        end

      :exit, e ->
        case e do
          {:timeout, c} -> {:timeout, c}
          _ -> {:error, {:exit, e}}
        end
    end # end try
  end

  @doc """

  """
  def server_kill!(pool_server, context \\ nil, options \\ %{}), do: pool_server.router().internal_cast({:server_kill!, options}, context, options)

  @doc """

  """
  def service_health_check!(pool_server, %Noizu.ElixirCore.CallingContext{} = context) do
    pool_server.router().internal_system_call({:health_check!, %{}}, context)
  end

  def service_health_check!(pool_server, health_check_options, %Noizu.ElixirCore.CallingContext{} = context) do
    pool_server.router().internal_system_call({:health_check!, health_check_options}, context)
  end

  def service_health_check!(pool_server, health_check_options, %Noizu.ElixirCore.CallingContext{} = context, options) do
    pool_server.router().internal_system_call({:health_check!, health_check_options}, context, options)
  end


  @doc """

  """
  def record_service_event!(_pool_server, _event, _details, _context, _options) do
    Logger.error("Service Manager V2 record_service_event NYI")
    :ok
  end

end