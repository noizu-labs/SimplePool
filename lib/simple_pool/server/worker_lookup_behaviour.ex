defmodule Noizu.SimplePool.WorkerLookupBehaviour do
  @callback update_server!(module :: atom, node :: any, context :: any) :: :ok
  @callback enable_server!(module :: atom, node :: any, context :: any) :: :ok
  @callback disable_server!(module :: atom, node :: any, context :: any) :: :ok

  @callback force_check_worker!(atom, any, context :: any) :: {boolean, pid|any}
  @callback check_worker!(any, atom, any, context :: any) :: {boolean, pid|any}

  @callback get_reg_worker!(atom, any, context :: any) :: {boolean, pid|any}
  @callback dereg_worker!(atom, any, context :: any) :: :ok | :error
  @callback reg_worker!(atom, any, pid, context :: any) :: :ok | {:error, any}
  @callback clear_process!(atom, any, node_pid :: any, context :: any) :: :ok | :error
  @callback get_distributed_nodes!(atom, any, context :: any) :: list | nil | {:error, term}

  defmodule DefaultImplementation do
    def update_server!(_mod, _target_node \\ :auto, _context \\ nil), do: :ok
    def enable_server!(_mod, _target_node \\ :auto, _context \\ nil), do: :ok
    def disable_server!(_mod, _target_node \\ :auto, _context \\ nil), do: :ok


    def get_distributed_nodes!(mod, nmid, _context \\ nil) do
      # Must be implemented by api user.
      [node()]
    end

    def reg_worker!(mod, nmid, pid, _context \\ nil) do
      :ets.insert(mod.lookup_table(), {nmid, pid})
    end

    def clear_process!(mod, nmid, _pid_node, _context \\ nil) do
      :ets.delete(mod.lookup_table(), nmid)
    end

    def dereg_worker!(mod, nmid, _context \\ nil) do
      :ets.delete(mod.lookup_table(), nmid)
    end

    def check_worker!(pid_node, mod, nmid, _context \\ nil), do: raise "not implemented"
    def force_check_worker!(mod, nmid, _context \\ nil), do: raise "not implemented"

    def get_reg_worker!(mod, nmid, _context \\ nil) do
      case :ets.info(mod.lookup_table()) do
        :undefined -> {false, :nil}
        _ ->
          case :ets.lookup(mod.lookup_table(), nmid) do
             [{_key, pid}] ->
                if Process.alive?(pid) do
                  {true, pid}
                else
                  dereg_worker!(mod, nmid)
                  {false, :nil}
                end
              [] ->
                dereg_worker!(mod, nmid)
                {false, :nil}
          end
      end
    end
  end # end defmodule DefaultImplementation
end # end defmodule
