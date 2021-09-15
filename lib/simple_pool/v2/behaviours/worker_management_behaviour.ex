#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerManagementBehaviour do
  require Logger
  @callback count_supervisor_children() :: any
  @callback group_supervisor_children(any) :: any
  @callback active_supervisors() :: any

  @callback supervisor_by_index(any) :: any
  @callback available_supervisors() :: any
  @callback supervisor_current_supervisor(any) :: any

  @callback worker_start(any, any) :: any
  @callback worker_start(any, any, any) :: any
  @callback worker_terminate(any, any, any, any) :: any
  @callback worker_remove(any, any, any, any) :: any
  @callback worker_add!(any, any, any) :: any

  @callback worker_load!(any, any, any) :: any
  @callback worker_ref!(any, any) :: any

  @callback migrate!(any, any, any, any) :: any
  @callback bulk_migrate!(any, any, any) :: any

  @callback workers!(any) :: any
  @callback workers!(any, any) :: any
  @callback workers!(any, any, any) :: any


  @callback terminate!(any, any, any) :: any
  @callback remove!(any, any, any) :: any
  @callback accept_transfer!(any, any, any, any) :: any
  @callback lock!(any, any) :: any
  @callback release!(any, any) :: any


  @type lock_response :: {:ack, record :: any} | {:nack, {details :: any, record :: any}} | {:nack, details :: any} | {:error, details :: any}

  @callback host!(ref :: tuple, Noizu.ElixirCore.CallingContext.t | nil, opts :: Map.t) :: {:ok, atom} | {:spawn, atom} | {:error, details :: any} | {:restricted, atom}
  @callback record_event!(ref :: tuple, event :: atom, details :: any, Noizu.ElixirCore.CallingContext.t | nil, opts :: Map.t) :: any
  @callback events!(ref :: tuple, Noizu.ElixirCore.CallingContext.t | nil, opts :: Map.t) :: list

  @callback register!(ref :: tuple, Noizu.ElixirCore.CallingContext.t | nil, opts :: Map.t) :: any
  @callback unregister!(ref :: tuple, Noizu.ElixirCore.CallingContext.t | nil, opts :: Map.t) :: any

  @callback process!(ref :: tuple, server :: module, Noizu.ElixirCore.CallingContext.t | nil, opts :: Map.t) :: lock_response
  @callback obtain_lock!(ref :: tuple, Noizu.ElixirCore.CallingContext.t | nil, opts :: Map.t) :: lock_response
  @callback release_lock!(ref :: tuple, Noizu.ElixirCore.CallingContext.t | nil, opts :: Map.t) :: lock_response



  defmodule DefaultProvider do
    defmacro __using__(_options) do
      quote do
        @pool_server Module.split(__MODULE__) |> Enum.slice(0 .. -2) |> Module.concat()
        alias Noizu.SimplePool.V2.WorkerManagement.WorkerManagementProvider, as: Provider

        @doc """
        Count children of all worker supervisors.
        """
        def count_supervisor_children(), do: Provider.count_supervisor_children(@pool_server)

        @doc """
        Group supervisor children by user provided method.
        """
        def group_supervisor_children(group_fun), do: Provider.group_supervisor_children(@pool_server, group_fun)

        @doc """
         Get list of active worker supervisors.
        """
        def active_supervisors(), do: Provider.active_supervisors(@pool_server)

        @doc """
         Get a supervisor module by index position.
        """
        def supervisor_by_index(index), do: Provider.supervisor_by_index(@pool_server, index)

        @doc """
          Return list of available worker supervisors.
        """
        def available_supervisors(), do: Provider.available_supervisors(@pool_server)

        @doc """
         Return supervisor responsible for a specific worker.
        """
        def current_supervisor(ref), do: Provider.current_supervisor(@pool_server, ref)

        @doc """

        """
        def worker_start(ref, transfer_state, context), do: Provider.worker_start(@pool_server, ref, transfer_state, context)

        @doc """

        """
        def worker_start(ref, context), do: Provider.worker_start(@pool_server, ref, context)

        @doc """

        """
        def worker_terminate(ref, context, options \\ %{}), do: Provider.worker_terminate(@pool_server, ref, context, options)

        @doc """

        """
        def worker_remove(ref, context, options \\ %{}), do: Provider.worker_remove(@pool_server, ref, context, options)

        @doc """

        """
        def worker_add!(ref, context \\ nil, options \\ %{}), do: Provider.worker_add!(@pool_server, ref, context, options)

        @doc """

        """
        def bulk_migrate!(transfer_server, context, options), do: Provider.bulk_migrate!(@pool_server, transfer_server, context, options)

        @doc """

        """
        def migrate!(ref, rebase, context \\ nil, options \\ %{}), do: Provider.migrate!(@pool_server, ref, rebase, context, options)

        @doc """

        """
        def worker_load!(ref, context \\ nil, options \\ %{}), do: Provider.worker_load!(@pool_server, ref, context, options)


        @doc """

        """
        def worker_ref!(identifier, context \\ nil), do: Provider.worker_ref!(@pool_server, identifier, context)

        # @todo we should tweak function signatures for workers! method.
        @doc """

        """
        def workers!(server, %Noizu.ElixirCore.CallingContext{} = context), do: Provider.workers!(@pool_server, server, context)
        def workers!(server, %Noizu.ElixirCore.CallingContext{} = context, options), do: Provider.workers!(@pool_server, server, context, options)
        def workers!(%Noizu.ElixirCore.CallingContext{} = context), do: Provider.workers!(@pool_server, context)
        def workers!(%Noizu.ElixirCore.CallingContext{} = context, options), do: Provider.workers!(@pool_server, context, options)
        def workers!(host, service_entity, %Noizu.ElixirCore.CallingContext{} = context), do: Provider.workers!(@pool_server, host, service_entity, context)
        def workers!(host, service_entity, %Noizu.ElixirCore.CallingContext{} = context, options), do: Provider.workers!(@pool_server, host, service_entity, context, options)

        @doc """

        """
        def terminate!(ref, context, options), do: Provider.terminate!(@pool_server, ref, context, options)

        @doc """

        """
        def remove!(ref, context, options), do: Provider.remove!(@pool_server, ref, context, options)


        @doc """

        """
        def accept_transfer!(ref, state, context \\ nil, options \\ %{}), do: Provider.accept_transfer!(@pool_server, ref, state, context, options)

        @doc """

        """
        def lock!(context, options \\ %{}), do: Provider.lock!(@pool_server, context, options)

        @doc """

        """
        def release!(context, options \\ %{}), do: Provider.release!(@pool_server, context, options)






        def host!(ref, context, options \\ %{}), do: Provider.host!(@pool_server, ref, context, options)
        def record_event!(ref, event, details, context, options \\ %{}), do: Provider.record_event!(@pool_server, ref, event, details, context, options)
        def events!(ref, context, options \\ %{}), do: Provider.events!(@pool_server, ref, context, options)
        def set_node!(ref, context, options \\ %{}), do: Provider.set_node!(@pool_server, ref, context, options)
        def register!(ref, context, options \\ %{}), do: Provider.register!(@pool_server, ref, context, options)
        def unregister!(ref, context, options \\ %{}), do: Provider.unregister!(@pool_server, ref, context, options)
        def obtain_lock!(ref, context, options \\ %{}), do: Provider.obtain_lock!(@pool_server, ref, context, options)
        def release_lock!(ref, context, options \\ %{}), do: Provider.release_lock!(@pool_server, ref, context, options)
        def process!(ref, context, options \\ %{}), do: Provider.process!(@pool_server, ref, context, options)


        defoverridable [
          count_supervisor_children: 0,
          group_supervisor_children: 1,

          active_supervisors: 0,
          supervisor_by_index: 1,
          available_supervisors: 0,
          current_supervisor: 1,


          worker_start: 2,
          worker_start: 3,
          worker_terminate: 3,
          worker_remove: 3,
          worker_add!: 3,

          worker_load!: 3,
          worker_ref!: 2,

          migrate!: 4,
          bulk_migrate!: 3,

          workers!: 1,
          workers!: 2,
          workers!: 3,
          workers!: 4,

          terminate!: 3,
          remove!: 3,
          accept_transfer!: 4,
          lock!: 2,
          release!: 2,



          host!: 3,
          record_event!: 5,
          events!: 3,
          set_node!: 3,
          register!: 3,
          unregister!: 3,
          obtain_lock!: 3,
          release_lock!: 3,
          process!: 3

        ]
      end
    end
  end
end