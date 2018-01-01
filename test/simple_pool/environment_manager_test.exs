defmodule Noizu.SimplePool.EnvironmentManagerTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  require Logger

  alias Noizu.SimplePool.Support.TestTwoPool
  alias Noizu.SimplePool.Support.TestPool

  @context Noizu.ElixirCore.CallingContext.system(%{})


  @tag capture_log: true
  test "process forwarding across nodes" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref(:two)
    TestTwoPool.Server.test_s_call!(ref, :bannana, @context)
    {_ref, _pid, host} = TestTwoPool.Server.fetch(ref, :process)
    assert host == :"second@127.0.0.1"
  end

  @tag capture_log: true
  test "process forwarding origin node" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    TestPool.Server.test_s_call!(ref, :bannana, @context)
    {_ref, _pid, host} = TestPool.Server.fetch(ref, :process)
    assert host == :"first@127.0.0.1"
  end

  @tag capture_log: true
  test "process across node" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref(:two)
    TestTwoPool.Server.test_s_call!(ref, :bannana, @context)
    {:ack, pid} = Noizu.SimplePool.WorkerLookupBehaviour.Dynamic.process!(ref, Noizu.SimplePool.Support.TestTwoPool, Noizu.SimplePool.Support.TestTwoPool.Server, @context)
    assert is_pid(pid)
  end

  @tag capture_log: true
  test "process origin node" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    TestPool.Server.test_s_call!(ref, :bannana, @context)
    {:ack, pid} = Noizu.SimplePool.WorkerLookupBehaviour.Dynamic.process!(ref, Noizu.SimplePool.Support.TestPool, Noizu.SimplePool.Support.TestPool.Server, @context)
    assert is_pid(pid)
  end

  @tag capture_log: true
  test "process hint table" do
    #assert true == false
  end

  @tag capture_log: true
  test "process events" do
    #assert true == false
  end

  @tag capture_log: true
  test "process health_index" do
    #assert true == false
  end

  @tag capture_log: true
  test "server events" do
    #assert true == false
  end

  @tag capture_log: true
  test "server health_index" do
    #assert true == false
  end

  @tag capture_log: true
  test "lock server" do
    #assert true == false
  end

  @tag capture_log: true
  test "release server" do
    #assert true == false
  end

  @tag capture_log: true
  test "rebalance server" do
    #assert true == false
  end

end

