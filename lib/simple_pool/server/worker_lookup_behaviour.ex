defmodule Noizu.SimplePool.WorkerLookupBehaviour do
  @callback update_server!(module :: atom, node :: any, context :: any) :: :ok
  @callback enable_server!(module :: atom, node :: any, context :: any) :: :ok
  @callback disable_server!(module :: atom, node :: any, context :: any) :: :ok

  @callback force_check_worker!(atom, any, context :: any) :: {boolean, pid|any}
  @callback check_worker!(any, atom, any, context :: any) :: {boolean, pid|any}

  @callback record_timeout!(atom, any, {integer, integer}, context :: any) :: :ok | :error | :reap
  @callback record_restart!(atom, any, integer, context :: any) :: :ok | :error
  @callback is_locked?(atom, any, integer, context :: any) :: {boolean, pid|any}
  @callback queue_for_reap!(atom, any, integer, context :: any) :: {boolean, pid|any}
  @callback get_worker_node!(atom, any) :: :error | atom

  @callback get_reg_worker!(atom, any, context :: any) :: {boolean, pid|any}
  @callback dereg_worker!(atom, any, context :: any) :: :ok | :error
  @callback reg_worker!(atom, any, pid, context :: any) :: :ok | {:error, any}
  @callback clear_process!(atom, any, node_pid :: any, context :: any) :: :ok | :error
  @callback get_distributed_nodes!(atom, any, context :: any) :: list | nil | {:error, term}

  defmodule DefaultImplementation do
    def update_server!(_mod, _target_node \\ :auto, _context \\ nil), do: :ok
    def enable_server!(_mod, _target_node \\ :auto, _context \\ nil), do: :ok
    def disable_server!(_mod, _target_node \\ :auto, _context \\ nil), do: :ok


    def record_timeout!(_mod, _ref, {_time, _timeout}, _context) do
      :ok
    end

    def record_restart!(_mod, _ref, _time, _context) do
      :ok
    end

    def is_locked?(_mod, _ref, _time, _context) do
      false
    end

    def queue_for_reap!(_mod, _server, _ref, _time, _context) do
      :proceed
    end

    def get_worker_node(_mod, _ref), do: node()

    def get_distributed_nodes!(mod, ref, _context \\ nil) do
      # Must be implemented by api user.
      [node()]
    end

    def reg_worker!(mod, ref, pid, _context \\ nil) do
      :ets.insert(mod.lookup_table(), {ref, pid})
    end

    def clear_process!(mod, ref, _pid_node, _context \\ nil) do
      :ets.delete(mod.lookup_table(), ref)
    end

    def dereg_worker!(mod, ref, _context \\ nil) do
      :ets.delete(mod.lookup_table(), ref)
    end

    def check_worker!(pid_node, mod, ref, _context \\ nil), do: raise "not implemented"
    def force_check_worker!(mod, ref, _context \\ nil), do: raise "not implemented"

    def get_reg_worker!(mod, ref, _context \\ nil) do
      case :ets.info(mod.lookup_table()) do
        :undefined -> {false, :nil}
        _ ->
          case :ets.lookup(mod.lookup_table(), ref) do
             [{_key, pid}] ->
                if Process.alive?(pid) do
                  {true, pid}
                else
                  dereg_worker!(mod, ref)
                  {false, :nil}
                end
              [] ->
                dereg_worker!(mod, ref)
                {false, :nil}
          end
      end
    end
  end # end defmodule DefaultImplementation
end # end defmodule
