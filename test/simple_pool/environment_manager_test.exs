defmodule Noizu.SimplePool.EnvironmentManagerTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  require Logger

  @context Noizu.ElixirCore.CallingContext.system(%{})

  @tag capture_log: true
  test "work in progress" do
    assert true == false
  end

end

