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
    hint_1 = Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable.read!(Noizu.SimplePool.Support.TestPool)
    hint_2 = Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable.read!(Noizu.SimplePool.Support.TestTwoPool)
    hint_3 = Noizu.SimplePool.Database.MonitoringFramework.Service.HintTable.read!(Noizu.SimplePool.Support.TestThreePool)

    hint_1_keys = Map.keys(hint_1.hint)
    hint_2_keys = Map.keys(hint_2.hint)
    hint_3_keys = Map.keys(hint_3.hint)

    assert hint_1_keys == [{:"first@127.0.0.1", Noizu.SimplePool.Support.TestPool}]
    assert hint_2_keys == [{:"second@127.0.0.1", Noizu.SimplePool.Support.TestTwoPool}]
    assert hint_3_keys == [{:"first@127.0.0.1", Noizu.SimplePool.Support.TestThreePool}, {:"second@127.0.0.1", Noizu.SimplePool.Support.TestThreePool}]
  end

  @tag capture_log: true
  test "process events" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref(:two)
    TestTwoPool.Server.test_s_call!(ref, :bannana, @context)
    TestTwoPool.Server.kill!(ref, @context)
    Process.sleep(100)
    [start_event, terminate_event] = Noizu.SimplePool.Database.Dispatch.MonitorTable.read!(ref)
    assert start_event.event == :start
    assert terminate_event.event == :terminate

    service_events = Noizu.SimplePool.Database.MonitoringFramework.Service.EventTable.read!({:"second@127.0.0.1", Noizu.SimplePool.Support.TestTwoPool})
    start_event = List.first(service_events)
    assert start_event.entity.identifier == :start

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

