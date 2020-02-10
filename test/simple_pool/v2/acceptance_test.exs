#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.AcceptanceTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  require Logger

  @context Noizu.ElixirCore.CallingContext.system(%{})

  @tag :v2
  @tag capture_log: true
  test "Basic - Behaviour Overrides" do
    # Confirm we are able to override nested behaviour method declarations.
    assert Noizu.SimplePool.Support.TestV2TwoPool.banner("hello world") == :succesful_override
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - fetch" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    f = Noizu.SimplePool.Support.TestV2Pool.Server.fetch!(ref, :state)
    assert f.worker_ref == ref

    {_ref, pid, host} = Noizu.SimplePool.Support.TestV2Pool.Server.fetch!(ref, :process)
    assert host == :"first@127.0.0.1"
    p_info = Process.info(pid)
    assert p_info[:dictionary][:"$initial_call"] == {Noizu.SimplePool.Support.TestV2Pool.Worker, :init, 1}
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - ping" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    assert Noizu.SimplePool.Support.TestV2Pool.Server.ping(ref) == :pong
  end

  @tag :v2
  #@tag capture_log: true
  test "basic_functionality - s_call!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.test_s_call!(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :inner_state, @context)
    assert sut.data[:s_call!] == :bannana
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - s_cast!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.test_s_cast!(ref, :apple2, @context)
    Process.sleep(1000)
    temp = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :state, @context)
    IO.puts "TEMP STATE = : #{inspect temp, pretty: true, limit: :infinity}"
    sut = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :inner_state, @context)
    assert sut.data[:s_cast!] == :apple2
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - s_call" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.test_s_call(ref, :bannana, @context)
    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    sut = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :inner_state, @context)
    assert sut.data[:s_call] == nil

    Noizu.SimplePool.Support.TestV2Pool.test_s_call(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :inner_state, @context)
    assert sut.data[:s_call] == :bannana
  end

  @tag :v2
  test "basic_functionality - s_cast" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.test_s_cast(ref, :bannana, @context)
    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    process = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :process, @context)
    IO.inspect process, pretty: true,  limit: :infinity
    sut = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :inner_state, @context)
    assert sut.data[:s_cast] == nil

    Noizu.SimplePool.Support.TestV2Pool.test_s_cast(ref, :bannana, @context)
    process = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :process, @context)
    IO.inspect process, pretty: true,  limit: :infinity
    sut = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :inner_state, @context)
    assert sut.data[:s_cast] == :bannana
  end



  @tag :v2
  @tag capture_log: true
  test "basic_functionality fetch process" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    {rref, _process, server} = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :process, @context)
    assert rref == ref
    assert server == node()
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality fetch state" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    sut = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :state, @context)
    case sut do
      %Noizu.SimplePool.Worker.State{} -> assert true == true
      _ -> assert sut == :start
    end
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality fetch default" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    sut = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :inner_state, @context)
    case sut do
      %Noizu.SimplePool.Support.TestWorkerEntity{} -> assert true == true
      _ -> assert sut == :start
    end
  end

  @tag :v2
  #@tag capture_log: true
  test "basic_functionality kill process" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    {_rref, process, _server} = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :process, @context)
    Noizu.SimplePool.Support.TestV2Pool.kill!(ref, @context)

    # Test
    Process.sleep(3000)
    {rref2, process2, server2} = wait_for_restart(ref)
    assert rref2 == ref
    assert server2 == node()
    assert process != process2
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality crash process" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    {_rref, process, _server} = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :process, @context)
    try do
      Noizu.SimplePool.Support.TestV2Pool.crash!(ref, @context)
    rescue e -> :expected
    catch e -> :expected
    end

    # Test
    Process.sleep(3000)
    {rref2, process2, server2} = wait_for_restart(ref)
    assert rref2 == ref
    assert server2 == node()
    assert process != process2
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality health check - healthy" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    Process.sleep(1000)
    r = Noizu.SimplePool.Support.TestV2Pool.health_check!(ref, @context)

    # NOT YET IMPLEMENTED
    assert r == :nyi

    #assert r.status == :online
    #[start_event] = r.events
    #assert start_event.event == :start

  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality ping worker" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    sut = Noizu.SimplePool.Support.TestV2Pool.ping(ref,  @context)
    assert sut == :pong
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - get_direct_link" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    link = Noizu.SimplePool.Support.TestV2Pool.get_direct_link!(ref,  @context)
    assert link.handle == nil
    assert link.state == {:error, {:nack, {:host_error, {:nack, :no_registered_host}}}}

    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    {_rref, process, _server} = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :process, @context)
    link = Noizu.SimplePool.Support.TestV2Pool.get_direct_link!(ref,  @context)
    assert link.handle == process
    assert link.state == :valid
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - link_forward!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    link = Noizu.SimplePool.Support.TestV2Pool.get_direct_link!(ref,  @context)
    {:ok, updated_link} = Noizu.SimplePool.Support.TestV2Pool.link_forward!(link, {:test_s_cast, 1234},  @context, %{spawn: true})

    Noizu.SimplePool.Support.TestV2Pool.Server.wake!(ref, :state, @context)
    sut = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :inner_state, @context)
    {_rref, process, _server} = Noizu.SimplePool.Support.TestV2Pool.fetch!(ref, :process, @context)

    assert sut.data.s_cast == 1234
    assert updated_link.handle == process
    assert updated_link.state == :valid
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - link_forward! - does not auto start" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    link = Noizu.SimplePool.Support.TestV2Pool.get_direct_link!(ref,  @context)
    {:error, updated_link} = Noizu.SimplePool.Support.TestV2Pool.link_forward!(link, {:test_s_cast, 1234},  @context)
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
    case Noizu.SimplePool.Support.TestV2Pool.wake!(ref, :process, @context) do
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
