if Mix.env == :test do
  defmodule Noizu.SimplePool.Test.Fixture.PoolFixture do
    use Noizu.SimplePool.Behaviour,
      default_modules: [:worker, :server, :pool_supervisor, :worker_supervisor]

      defmodule WorkerStateEntity do
        @behaviour Noizu.SimplePool.InnerStateBehaviour

        @type t :: %WorkerStateEntity{identifier: any}
        defstruct [identifier: :wip]

        def terminate_hook(_reason, _state), do: :ok
        def shutdown(_context, state), do: {:ok, state}

        def ref(identifier), do: {:ref, __MODULE__, identifier}

        def load(ref), do: load(ref, nil, nil)
        def load(ref, context), do: load(ref, nil, context)
        def load(_ref, _options, _context), do: %__MODULE__{}

        def call_forwarding(_type, _call, state), do: {:noreply, state}
        def call_forwarding(_type, _call, _from, state), do: {:reply, :nyi, state}

        def fetch(_options, _context, state), do: state
      end
  end
end
