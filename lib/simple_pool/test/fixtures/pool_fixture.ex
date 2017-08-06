if Mix.env == :test do
  defmodule Noizu.SimplePool.Test.Fixture.PoolFixture do
    use Noizu.SimplePool.Behaviour,
      default_modules: [:pool_supervisor, :worker_supervisor]
  end
end
