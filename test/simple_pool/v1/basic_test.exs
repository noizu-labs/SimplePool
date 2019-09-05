#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V1.BasicTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  require Logger

  @context Noizu.ElixirCore.CallingContext.system(%{})

  @tag :v1
  @tag capture_log: true
  test "basic_functionality - s_call!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.test_s_call!(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_call!] == :bannana
  end

  @tag :v1
  @tag capture_log: true
  test "basic_functionality - s_cast!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.test_s_cast!(ref, :apple, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_cast!] == :apple
  end

  @tag :v1
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

  @tag :v1
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

  @tag :v1
  @tag capture_log: true
  test "basic_functionality fetch process" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    {rref, _process, server} = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    assert rref == ref
    assert server == node()
  end

  @tag :v1
  @tag capture_log: true
  test "basic_functionality fetch state" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :state, @context)

    case sut do
      %Noizu.SimplePool.Worker.State{} -> assert true == true
      _ -> assert sut == :invalid
    end
  end

  @tag :v1
  @tag capture_log: true
  test "basic_functionality fetch default" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)

    case sut do
      %Noizu.SimplePool.Support.TestWorkerEntity{} -> assert true == true
      _ -> assert sut == :invalid
    end
  end

  @tag :v1
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

  @tag :v1
  @tag capture_log: true
  test "basic_functionality crash process" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    {_rref, process, _server} = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    try do
      Noizu.SimplePool.Support.TestPool.Server.crash!(ref, @context)
    rescue e -> :expected
    catch e -> :expected
    end

    # Test
    {rref2, process2, server2} = wait_for_restart(ref)
    assert rref2 == ref
    assert server2 == node()
    assert process != process2
  end

  @tag :v1
  @tag capture_log: true
  test "basic_functionality health check - healthy" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    Process.sleep(1000)
    r = Noizu.SimplePool.Support.TestPool.Server.health_check!(ref, @context)
    assert r.status == :online
    #[start_event] = r.events
    #assert start_event.event == :start

  end

  @tag :v1
  @tag capture_log: true
  test "basic_functionality ping worker" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.ping!(ref,  @context)
    assert sut == :pong
  end

  @tag capture_log: true
  test "basic_functionality - get_direct_link" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    link = Noizu.SimplePool.Support.TestPool.Server.get_direct_link!(ref,  @context)
    assert link.handle == nil
    assert link.state == {:error, {:nack, {:host_error, {:nack, :no_registered_host}}}}

    {_rref, process, _server} = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :process, @context)
    link = Noizu.SimplePool.Support.TestPool.Server.get_direct_link!(ref,  @context)
    assert link.handle == process
    assert link.state == :valid
  end

  @tag :v1
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

  @tag :v1
  @tag capture_log: true
  test "basic_functionality - link_forward! - does not auto start" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    link = Noizu.SimplePool.Support.TestPool.Server.get_direct_link!(ref,  @context)
    {:error, updated_link} = Noizu.SimplePool.Support.TestPool.Server.link_forward!(link, {:test_s_cast, 1234},  @context)
    assert updated_link.handle == nil
  end

  # @TODO - test process forwarding/process alive checking
  # @TODO - test migrate
  # @TODO - test reload
  # @TODO - test lazy load pool
  # @TODO - test immediate load pool
  # @TODO - flesh out server monitor and related functionality
  # @TODO - multi-node testing, migrate, s_call

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

      r = {:error, {:exit, {:noproc, _d}}} ->
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

      r = {:error, {:exit, _}} ->
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
