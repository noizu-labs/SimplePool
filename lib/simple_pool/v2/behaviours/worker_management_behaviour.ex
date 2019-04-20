#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerManagementBehaviour do
  require Logger
  @callback count_supervisor_children() :: any
  @callback group_supervisor_children(any) :: any
  @callback active_supervisors() :: any
  @callback worker_supervisors() :: any
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
  @callback worker_pid!(any, any, any) :: any

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

  defmacro __using__(_options) do
    quote do
      @server Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat()
      @router Module.concat(@server, Router)

      @doc """
      Count children of all worker supervisors.
      """
      def count_supervisor_children(), do: throw :pri0

      @doc """
      Group supervisor children by user provided method.
      """
      def group_supervisor_children(group_fun), do: throw :pri0

      @doc """
       Get list of active worker supervisors.
      """
      def active_supervisors(), do: throw :pri0

      @doc """
       Get list of all worker supervisors.
      """
      def worker_supervisors(), do: throw :pri0

      @doc """
       Get a supervisor module by index position.
      """
      def supervisor_by_index(index), do: throw :pri0

      @doc """
        Return list of available worker supervisors.
      """
      def available_supervisors(), do: throw :pri0

      @doc """
       Return supervisor responsible for a specific worker.
      """
      def current_supervisor(ref), do: throw :pri0

      @doc """

      """
      def worker_start(ref, transfer_state, context), do: throw :pri0

      @doc """

      """
      def worker_start(ref, context), do: throw :pri0

      @doc """

      """
      def worker_terminate(ref, sup, context, options \\ %{}), do: throw :pri0

      @doc """

      """
      def worker_remove(ref, sup, context, options \\ %{}), do: throw :pri0

      def worker_add!(ref, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: throw :pri0

      @doc """

      """
      def bulk_migrate!(transfer_server, context, options), do: throw :pri0

      @doc """

      """
      def migrate!(ref, rebase, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: throw :pri0

      @doc """

      """
      def worker_load!(ref, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: throw :pri0

      @doc """

      """
      def worker_ref!(identifier, _context \\ Noizu.ElixirCore.CallingContext.system(%{})), do: throw :pri0

      @doc """

      """
      def worker_pid!(ref, context \\ Noizu.ElixirCore.CallingContext.system(%{}), options \\ %{}), do: throw :pri0

      @doc """

      """
      def workers!(server, %Noizu.ElixirCore.CallingContext{} = context), do: throw :pri0
      def workers!(server, %Noizu.ElixirCore.CallingContext{} = context, options), do: throw :pri0
      def workers!(%Noizu.ElixirCore.CallingContext{} = context), do: throw :pri0
      def workers!(%Noizu.ElixirCore.CallingContext{} = context, options), do: throw :pri0

      @doc """

      """
      def terminate!(ref, context, options), do: throw :pri0

      @doc """

      """
      def remove!(ref, context, options), do: throw :pri0


      @doc """

      """
      def accept_transfer!(ref, state, context \\ nil, options \\ %{}), do: throw :pri0

      @doc """

      """
      def lock!(context, options \\ %{}), do: throw :pri0

      @doc """

      """
      def release!(context, options \\ %{}), do: throw :pri0


      defoverridable [
        count_supervisor_children: 0,
        group_supervisor_children: 1,

        active_supervisors: 0,
        supervisor_by_index: 1,
        available_supervisors: 0,
        current_supervisor: 1,

        worker_supervisors: 0,
        worker_start: 2,
        worker_start: 3,
        worker_terminate: 4,
        worker_remove: 4,
        worker_add!: 3,

        worker_load!: 3,
        worker_ref!: 2,
        worker_pid!: 3,

        migrate!: 4,
        bulk_migrate!: 3,

        workers!: 1,
        workers!: 2,
        workers!: 3,


        terminate!: 3,
        remove!: 3,
        accept_transfer!: 4,
        lock!: 2,
        release!: 2,

      ]
    end
  end
end