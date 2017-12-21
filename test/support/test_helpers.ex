defmodule Noizu.SimplePool.TestHelpers do
  def unique_ref(), do: {:ref, Noizu.SimplePool.Support.TestWorkerEntity, "test_#{inspect :os.system_time(:microsecond)}"}

end