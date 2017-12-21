defmodule Noizu.SimplePool.BasicTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  require Logger

  @context Noizu.ElixirCore.CallingContext.system(%{})

  @tag capture_log: true
  test "basic_functionality - s_call!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.test_s_call!(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_call!] == :bannana
  end

  @tag capture_log: true
  test "basic_functionality - s_cast!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.test_s_cast!(ref, :apple, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_cast!] == :apple
  end

  @tag capture_log: true
  test "basic_functionality - s_call" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.test_s_call(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_call] == nil

    Noizu.SimplePool.Support.TestPool.Server.test_s_call(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_call] == :bannana
  end

  @tag capture_log: true
  test "basic_functionality - s_cast" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.test_s_cast(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_cast] == nil

    Noizu.SimplePool.Support.TestPool.Server.test_s_cast(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_cast] == :bannana
  end

  @tag capture_log: true
  test "basic_functionality fetch process" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    {rref, _process, server} = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    assert rref == ref
    assert server == node()
  end

  @tag capture_log: true
  test "basic_functionality fetch state" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :state, @context)

    case sut do
      %Noizu.SimplePool.Worker.State{} -> assert true == true
      _ -> assert sut == :invalid
    end
  end

  @tag capture_log: true
  test "basic_functionality fetch default" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)

    case sut do
      %Noizu.SimplePool.Support.TestWorkerEntity{} -> assert true == true
      _ -> assert sut == :invalid
    end
  end

  @tag capture_log: true
  test "basic_functionality kill process" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    {_rref, process, _server} = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    Noizu.SimplePool.Support.TestPool.Server.kill!(ref, @context)

    # Test
    {rref2, process2, server2} = wait_for_restart(ref)
    assert rref2 == ref
    assert server2 == node()
    assert process != process2
  end


  @tag capture_log: true
  test "basic_functionality crash process" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    {_rref, process, _server} = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    Noizu.SimplePool.Support.TestPool.Server.crash!(ref, @context)

    # Test
    {rref2, process2, server2} = wait_for_restart(ref)
    assert rref2 == ref
    assert server2 == node()
    assert process != process2
  end

  @tag capture_log: true
  test "basic_functionality health check - healthy" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    r = Noizu.SimplePool.Support.TestPool.Server.health_check!(ref, @context)
    assert r.status == :online
    [start_event] = r.events
    assert start_event.event == :start

  end


  @tag capture_log: true
  test "basic_functionality health check - degraded" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)

    # simulate 3 recent crashes
    for _i <- 1..2 do
      Process.sleep(1000)
      Noizu.SimplePool.Support.TestPool.Server.kill!(ref, @context)
      {_r,_p, _s} = wait_for_restart(ref)
      # Force sleep so that terminate/start entries are unique (have different time entry)
    end


    r = Noizu.SimplePool.Support.TestPool.Server.health_check!(ref, @context)
    assert r.status == :degraded
    assert r.event_frequency.start == 3
    assert r.event_frequency.terminate == 2
    assert r.event_frequency.exit >= 2
  end


  @tag capture_log: true
  test "basic_functionality health check - critical" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)

    # simulate 3 recent crashes
    for _i <- 1..5 do
      Process.sleep(1000)
      Noizu.SimplePool.Support.TestPool.Server.kill!(ref, @context)
      {_r,_p, _s} = wait_for_restart(ref)
      # Force sleep so that terminate/start entries are unique (have different time entry)
    end

    r = Noizu.SimplePool.Support.TestPool.Server.health_check!(ref, @context)
    assert r.status == :critical
  end

  @tag capture_log: true
  test "basic_functionality ping worker" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.ping!(ref,  @context)
    assert sut == :pong
  end

  @tag capture_log: true
  test "record events pipes to log output" do
    assert capture_log(fn ->
      ref = Noizu.SimplePool.TestHelpers.unique_ref()
      Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    end) =~ "[RecordEvent :start]"
  end

  @tag capture_log: true
  test "basic_functionality - get_direct_link" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    link = Noizu.SimplePool.Support.TestPool.Server.get_direct_link!(ref,  @context)
    assert link.handle == nil
    assert link.state == {:error, {:nack, :not_registered}}

    {_rref, process, _server} = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    link = Noizu.SimplePool.Support.TestPool.Server.get_direct_link!(ref,  @context)
    assert link.handle == process
    assert link.state == :valid
  end


  @tag capture_log: true
  test "basic_functionality - link_forward!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    link = Noizu.SimplePool.Support.TestPool.Server.get_direct_link!(ref,  @context)
    {:ok, updated_link} = Noizu.SimplePool.Support.TestPool.Server.link_forward!(link, {:test_s_cast, 1234},  @context, %{spawn: true})
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    {_rref, process, _server} = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)

    assert sut.data.s_cast == 1234
    assert updated_link.handle == process
    assert updated_link.state == :valid
  end

  @tag capture_log: true
  test "basic_functionality - link_forward! - does not auto start" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    link = Noizu.SimplePool.Support.TestPool.Server.get_direct_link!(ref,  @context)
    {:error, updated_link} = Noizu.SimplePool.Support.TestPool.Server.link_forward!(link, {:test_s_cast, 1234},  @context)
    assert updated_link.handle == nil
  end


  # @TODO - update behaviour definitions
  # @TODO - cleanup method lists.
  # @TODO - flesh out server monitor and related functionality
  # @TODO - multi-node testing, migrate, s_call
  # @TODO - get rid of @timeout parameter, pass in options if desired.

  #--------------------------
  # helpers
  #--------------------------
  def wait_for_restart(ref, attempts \\ 10) do
    case Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context) do
      r = {:error, {:exit, {{%RuntimeError{}, _stack}, _call}}} ->
        if attempts > 0 do
          Process.sleep(5)
          wait_for_restart(ref, attempts - 1)
        else
          r
        end

      r = {:error, {:exit, {{:user_requested, _context}, _details}}} ->
        if attempts > 0 do
          Process.sleep(5)
          wait_for_restart(ref, attempts - 1)
        else
          r
        end
      r = {_r, _p, _s} -> r
    end
  end




end
