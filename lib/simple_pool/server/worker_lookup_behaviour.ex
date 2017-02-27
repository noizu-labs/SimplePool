defmodule Noizu.SimplePool.WorkerLookupBehaviour do
  @callback update_endpoint!() :: :ok
  @callback get_reg_worker!(atom, any) :: {boolean, pid|any}
  @callback dereg_worker!(atom, any) :: :ok | :error
  @callback reg_worker!(atom, any, pid) :: :ok | {:error, any}

  defmodule DefaultImplementation do
    def update_endpoint!(mod) do
      :ok
    end

    def reg_worker!(mod, nmid, pid) do
      :ets.insert(mod.lookup_table(), {nmid, pid})
    end

    def dereg_worker!(mod, nmid) do
      :ets.delete(mod.lookup_table(), nmid)
    end

    def get_reg_worker!(mod, nmid) do
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
