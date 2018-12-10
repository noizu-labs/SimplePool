#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Server.Supervisor.Behaviour do

  @callback count_supervisor_children(any) :: any
  @callback group_supervisor_children(any, any) :: any
  @callback active_supervisors(any) :: any
  @callback worker_supervisors(any) :: any
  @callback supervisor_by_index(any, any) :: any
  @callback available_supervisors(any) :: any
  @callback worker_supervisor_default(any) :: any
  @callback current_supervisor(any, any) :: any
  @callback worker_sup_start(any, any, any) :: any
  @callback worker_sup_start(any, any, any, any) :: any
  @callback worker_sup_terminate(any, any, any, any, any) :: any
  @callback worker_sup_remove(any, any, any, any, any) :: any
  @callback worker_add!(any, any, any, any) :: any

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      @behaviour Noizu.SimplePool.V2.Server.Supervisor.Behaviour
      @after_compile __MODULE__
      require Logger
      #-------------------
      #
      #-------------------
      def count_supervisor_children(module) do
        Enum.reduce(module.available_supervisors(), %{active: 0, specs: 0, supervisors: 0, workers: 0}, fn(s, acc) ->
          u = Supervisor.count_children(s)
          %{acc| active: acc.active + u.active, specs: acc.specs + u.specs, supervisors: acc.supervisors + u.supervisors, workers: acc.workers + u.workers}
        end)
      end

      #-------------------
      #
      #-------------------
      def group_supervisor_children(module, group_fun) do
        Task.async_stream(module.available_supervisors(),
          fn(s) ->
            children = Supervisor.which_children(s)
            sg = Enum.reduce(children, %{},
              fn(worker, acc) ->
                g = group_fun.(worker)
                if g do
                  update_in(acc, [g], &((&1 || 0) + 1))
                else
                  acc
                end
              end)
            {s, sg}
          end, timeout: 60_000)
        |> Enum.reduce(%{total: %{}}, fn(outcome, acc) ->
          case outcome do
            {:ok, {s, sg}} ->
              total = Enum.reduce(sg, acc.total, fn({g, c}, a) ->  update_in(a, [g], &((&1 || 0) ++ c)) end)
              acc = acc
                    |> put_in([s], sg)
                    |> put_in([:total], total)
            _ -> acc
          end
        end)
      end

      #-------------------
      #
      #-------------------
      def active_supervisors(module) do
        module.superviser_meta()[:active_supervisors]
      end

      #-------------------
      #
      #-------------------
      def worker_supervisors(module) do
        module.superviser_meta()[:worker_supervisors]
      end

      #-------------------
      #
      #-------------------
      def supervisor_by_index(module, index) do
        module.worker_supervisors()[index]
      end

      #-------------------
      #
      #-------------------
      def available_supervisors(module) do
        module.superviser_meta()[:available_supervisors]
      end

      #-------------------
      #
      #-------------------
      def worker_supervisor_default(module) do
        module.superviser_meta()[:default_supervisor]
      end

      #-------------------
      #
      #-------------------
      def current_supervisor(module, ref) do
        num_supervisors = module.active_supervisors()
        if num_supervisors == 1 do
          module.worker_supervisor_default()
        else
          hint = module.supervisor_hint(ref)
          pick = rem(hint, num_supervisors) + 1
          module.supervisor_by_index(pick)
        end
      end

      #-------------------
      #
      #-------------------
      def worker_sup_start(module, ref, transfer_state, context) do
        worker_sup = module.current_supervisor(ref)
        childSpec = worker_sup.child(ref, transfer_state, context)
        case Supervisor.start_child(worker_sup, childSpec) do
          {:ok, pid} -> {:ack, pid}
          {:error, {:already_started, pid}} ->
            timeout = module.meta()[:timeout]
            call = {:transfer_state, {:state, transfer_state, time: :os.system_time(:second)}}
            extended_call = module.extended_call(ref, timeout, call, context)
            GenServer.cast(pid, extended_call)
            Logger.warn(fn ->"#{module} attempted a worker_transfer on an already running instance. #{inspect ref} -> #{inspect node()}@#{inspect pid}" end)
            {:ack, pid}
          {:error, :already_present} ->
            # We may no longer simply restart child as it may have been initilized
            # With transfer_state and must be restarted with the correct context.
            Supervisor.delete_child(worker_sup, ref)
            case Supervisor.start_child(worker_sup, childSpec) do
              {:ok, pid} -> {:ack, pid}
              {:error, {:already_started, pid}} -> {:ack, pid}
              error -> error
            end
          error -> error
        end # end case
      end # endstart/3

      #-------------------
      #
      #-------------------
      def worker_sup_start(module, ref, context) do
        worker_sup = module.current_supervisor(ref)
        childSpec = worker_sup.child(ref, context)
        case Supervisor.start_child(worker_sup, childSpec) do
          {:ok, pid} -> {:ack, pid}
          {:error, {:already_started, pid}} ->
            {:ack, pid}
          {:error, :already_present} ->
            # We may no longer simply restart child as it may have been initilized
            # With transfer_state and must be restarted with the correct context.
            Supervisor.delete_child(worker_sup, ref)
            case Supervisor.start_child(worker_sup, childSpec) do
              {:ok, pid} -> {:ack, pid}
              {:error, {:already_started, pid}} -> {:ack, pid}
              error -> error
            end
          error -> error
        end # end case
      end # endstart/3

      #-------------------
      #
      #-------------------
      def worker_sup_terminate(module, ref, sup, context, options) do
        worker_sup = module.current_supervisor(ref)
        Supervisor.terminate_child(worker_sup, ref)
        Supervisor.delete_child(worker_sup, ref)
      end # end remove/3

      #-------------------
      #
      #-------------------
      def worker_sup_remove(module, ref, _sup, context, options) do
        graceful_stop = module.supervisor_meta()[:graceful_stop]
        shutdown_timeout = module.supervisor_meta()[:shutdown_timeout]

        g = if Map.has_key?(options, :graceful_stop), do: options[:graceful_stop], else: graceful_stop
        if g do
          module.s_call(ref, {:shutdown, [force: true]}, context, options, shutdown_timeout)
        end
        worker_sup = module.current_supervisor(ref)
        Supervisor.terminate_child(worker_sup, ref)
        Supervisor.delete_child(worker_sup, ref)
      end # end remove/3

      #-------------------
      #
      #-------------------
      def worker_add!(module, ref, context, options) do
        options_b = put_in(options, [:spawn], true)
        ref = module.worker_ref!(ref)
        module.worker_lookup_handler().process!(ref, module, context, options_b)
      end















      def run_on_host(module, ref, mfa, context, options, timeout), do: throw "PRI0"
      def cast_to_host(module, ref, mfa, context, options, timeout), do: throw "PRI0"
      def remove!(module, ref, context, options), do: throw "PRI0"
      def terminate!(module, ref, context, options), do: throw "PRI0"
      def bulk_migrate!(module, transfer_server, context, options), do: throw "PRI0"
      def worker_migrate!(module, ref, rebase, context, options), do: throw "PRI0"
      def worker_load!(module, ref, context, options), do: throw "PRI0"
      def worker_ref!(module, identifier, context), do: throw "PRI0"
      def worker_pid!(module, ref, context , options), do: throw "PRI0"

      defoverridable [
        count_supervisor_children: 1,
        group_supervisor_children: 2,
        active_supervisors: 1,
        worker_supervisors: 1,
        supervisor_by_index: 2,
        available_supervisors: 1,
        worker_supervisor_default: 1,
        current_supervisor: 2,
        worker_sup_start: 3,
        worker_sup_start: 4,
        worker_sup_terminate: 5,
        worker_sup_remove: 5,
        worker_add!: 4,
      ]




      # Make sure the Worker is valid
      def __after_compile__(_env, _bytecode) do
        required_methods = [
          count_supervisor_children: 1,
          group_supervisor_children: 2,
          active_supervisors: 1,
          worker_supervisors: 1,
          supervisor_by_index: 2,
          available_supervisors: 1,
          worker_supervisor_default: 1,
          current_supervisor: 2,
          worker_sup_start: 3,
          worker_sup_start: 4,
          worker_sup_terminate: 5,
          worker_sup_remove: 5,
          worker_add!: 4,
        ]

        missing_methods = required_methods
                          |> Enum.map(fn(m) -> unless Module.defines?(__MODULE__, m), do: m end)
                          |> Enum.filter(&(&1 != nil))

        if length(missing_methods) > 0 do
          missing = missing_methods
                    |> Enum.map(fn({method, arity}) -> "- must export a #{method}/#{arity} method" end)
                    |> Enum.join("\n")
          raise "#{__MODULE__} - missing required methods.\n#{missing}"
        end
      end

    end
  end
end