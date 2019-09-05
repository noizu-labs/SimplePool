#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V1.EnvironmentManagerTest do
  use ExUnit.Case, async: false

  #import ExUnit.CaptureLog
  require Logger

  alias Noizu.SimplePool.Support.TestPool
  alias Noizu.SimplePool.Support.TestTwoPool
  alias Noizu.SimplePool.Support.TestThreePool

  alias Noizu.SimplePool.MonitoringFramework.LifeCycleEvent
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
  test "service hint table" do
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
  test "service health_check" do
    health_check = TestPool.Server.service_health_check!(@context)
    assert Enum.member?([:online, :degraded, :critical], health_check.status)
    assert health_check.health_index > 0
    assert health_check.health_index < 5
  end

    @tag capture_log: true
  test "service health_index" do

    current_time = DateTime.utc_now()
    ct = DateTime.to_unix(current_time)

    definition = %Noizu.SimplePool.MonitoringFramework.Service.Definition{
      identifier: {:"second@127.0.0.1", Noizu.SimplePool.Support.TestTwoPool},
      server: :"second@127.0.0.1",
      pool: Noizu.SimplePool.Support.TestTwoPool.Server,
      supervisor: Noizu.SimplePool.Support.TestTwoPool.PoolSupervisor,
      time_stamp: current_time,
      hard_limit: 200,
      soft_limit: 150,
      target: 100,
    }

    events = [
      %LifeCycleEvent{identifier: :start, time_stamp: DateTime.from_unix!(ct - 60*20)},
      %LifeCycleEvent{identifier: :start, time_stamp: DateTime.from_unix!(ct - 60*9)},
      %LifeCycleEvent{identifier: :exit, time_stamp: DateTime.from_unix!(ct - 60*8)},
      %LifeCycleEvent{identifier: :start, time_stamp: DateTime.from_unix!(ct - 60*7)},
      %LifeCycleEvent{identifier: :terminate, time_stamp: DateTime.from_unix!(ct - 60*6)},
      %LifeCycleEvent{identifier: :start, time_stamp: DateTime.from_unix!(ct - 60*5)},
      %LifeCycleEvent{identifier: :timeout, time_stamp: DateTime.from_unix!(ct - 60*4)},
      %LifeCycleEvent{identifier: :timeout, time_stamp: DateTime.from_unix!(ct - 60*3)},
      %LifeCycleEvent{identifier: :timeout, time_stamp: DateTime.from_unix!(ct - 60*2)}
    ]

    {hi_1, li_1, ei_1} = Noizu.SimplePool.Server.ProviderBehaviour.Default.health_tuple(definition, %{active: 0}, events, ct)
    expected_weight = (
        (:math.pow((60/600), 2) * 1.0) +
        (:math.pow((120/600), 2) * 0.75) +
        (:math.pow((180/600), 2) * 1.0) +
        (:math.pow((240/600), 2) * 1.5) +
        (:math.pow((300/600), 2) * 1.0) +
        (:math.pow((360/600), 2) * 0.35) +
        (:math.pow((420/600), 2) * 0.35) +
        (:math.pow((480/600), 2) * 0.35)
      )

    assert hi_1 == expected_weight
    assert li_1 == 0
    assert ei_1 == expected_weight


    {hi_2, _li_2, _ei_2} = Noizu.SimplePool.Server.ProviderBehaviour.Default.health_tuple(definition, %{active: 101}, events, ct)
    assert hi_2 == (expected_weight + 1.0)

    {hi_2, _li_2, _ei_2} = Noizu.SimplePool.Server.ProviderBehaviour.Default.health_tuple(definition, %{active: 151}, events, ct)
    assert hi_2 == (expected_weight + 4.0)

    {hi_3, _li_3, _ei_3} = Noizu.SimplePool.Server.ProviderBehaviour.Default.health_tuple(definition, %{active: 201}, events, ct)
    assert hi_3 == (expected_weight + 12.0)
  end

  @tag :lock
  @tag capture_log: true
  test "lock and release server" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref(:two)
    pre_lock = TestTwoPool.Server.test_s_call!(ref, :bannana, @context)
    assert pre_lock == :s_call!
    Noizu.MonitoringFramework.EnvironmentPool.Server.lock_server(:"second@127.0.0.1", :all, @context, %{})
    :ok = Noizu.SimplePool.TestHelpers.wait_hint_lock(Noizu.SimplePool.TestHelpers.unique_ref(:two), TestTwoPool.Server, @context)
    ref2 = Noizu.SimplePool.TestHelpers.unique_ref(:two)
    post_lock = TestTwoPool.Server.test_s_call!(ref2, :bannana, @context)
    Noizu.MonitoringFramework.EnvironmentPool.Server.release_server(:"second@127.0.0.1", :all, @context, %{})
    assert post_lock == {:error, {:host_pick, {:nack, :none_available}}}
    :ok = Noizu.SimplePool.TestHelpers.wait_hint_release(ref2, TestTwoPool.Server, @context)

    post_release = TestTwoPool.Server.test_s_call!(ref2, :bannana, @context)
    assert post_release == :s_call!
  end


  @tag :wip
  @tag :rebalance
  @tag capture_log: false
  test "optomized rebalance server" do

    for _i <- 0 .. 200 do
      :s_call! = Noizu.SimplePool.TestHelpers.unique_ref(:one)
                 |> TestPool.Server.test_s_call!(:bananda, @context)

      :s_call! = Noizu.SimplePool.TestHelpers.unique_ref(:two)
                 |> TestTwoPool.Server.test_s_call!(:fananda, @context)

      :s_call! = Noizu.SimplePool.TestHelpers.unique_ref(:three)
                 |> TestThreePool.Server.test_s_call!(:labanda, @context)
    end

    #@TODO wait for all to spawn with out spin lock
    Process.sleep(2_000)

    Noizu.MonitoringFramework.EnvironmentPool.Server.lock_server(:"second@127.0.0.1", :all, @context, %{})
    :ok = Noizu.SimplePool.TestHelpers.wait_hint_lock(Noizu.SimplePool.TestHelpers.unique_ref(:two), TestTwoPool.Server, @context)

    for _i <- 0 .. 100 do
      :s_call! = Noizu.SimplePool.TestHelpers.unique_ref(:three)
                 |> TestThreePool.Server.test_s_call!(:labanda, @context)
    end

    #@TODO wait for all to spawn with out spin lock
    Process.sleep(2_000)

    Noizu.MonitoringFramework.EnvironmentPool.Server.release_server(:"second@127.0.0.1", :all, @context, %{})
    :ok = Noizu.SimplePool.TestHelpers.wait_hint_release(Noizu.SimplePool.TestHelpers.unique_ref(:two), TestTwoPool.Server, @context)

    #@TODO wait for all to spawn with out spin lock
    Process.sleep(2_000)

    # @TODO wait for state of last started process to be online.


    {:ack, chk1_1} = TestThreePool.Server.workers!(:"first@127.0.0.1", @context, %{})
    {:ack, chk1_2} = TestThreePool.Server.workers!(:"second@127.0.0.1", @context, %{})

    {:ack, _details} = Noizu.MonitoringFramework.EnvironmentPool.Server.optomized_rebalance([:"first@127.0.0.1"], [:"first@127.0.0.1", :"second@127.0.0.1"], MapSet.new([TestPool, TestTwoPool, TestThreePool]), @context, %{sync: true})

    Process.sleep(2_000)
    # @TODO wait for server of last scheduled to transfer to change
    # context = Noizu.ElixirCore.CallingContext.system(%{})
    {:ack, chk2_1} = TestThreePool.Server.workers!(:"first@127.0.0.1", @context, %{})
    {:ack, chk2_2} = TestThreePool.Server.workers!(:"second@127.0.0.1", @context, %{})

    delta1 = abs(length(chk1_1) - length(chk1_2))
    delta2 = abs(length(chk2_1) - length(chk2_2))

    assert delta1 > 50
    assert delta2 < 10

  end


  @tag :rebalance
  @tag capture_log: false
  test "rebalance server" do

    for _i <- 0 .. 200 do
      :s_call! = Noizu.SimplePool.TestHelpers.unique_ref(:one)
      |> TestPool.Server.test_s_call!(:bananda, @context)

      :s_call! = Noizu.SimplePool.TestHelpers.unique_ref(:two)
      |> TestTwoPool.Server.test_s_call!(:fananda, @context)

      :s_call! = Noizu.SimplePool.TestHelpers.unique_ref(:three)
      |> TestThreePool.Server.test_s_call!(:labanda, @context)
    end

    #@TODO wait for all to spawn with out spin lock
    Process.sleep(2_000)

    Noizu.MonitoringFramework.EnvironmentPool.Server.lock_server(:"second@127.0.0.1", :all, @context, %{})
    :ok = Noizu.SimplePool.TestHelpers.wait_hint_lock(Noizu.SimplePool.TestHelpers.unique_ref(:two), TestTwoPool.Server, @context)

    for _i <- 0 .. 100 do
      :s_call! = Noizu.SimplePool.TestHelpers.unique_ref(:three)
                 |> TestThreePool.Server.test_s_call!(:labanda, @context)
    end

    #@TODO wait for all to spawn with out spin lock
    Process.sleep(2_000)

    Noizu.MonitoringFramework.EnvironmentPool.Server.release_server(:"second@127.0.0.1", :all, @context, %{})
    :ok = Noizu.SimplePool.TestHelpers.wait_hint_release(Noizu.SimplePool.TestHelpers.unique_ref(:two), TestTwoPool.Server, @context)

    #@TODO wait for all to spawn with out spin lock
    Process.sleep(2_000)

    # @TODO wait for state of last started process to be online.


    {:ack, chk1_1} = TestThreePool.Server.workers!(:"first@127.0.0.1", @context, %{})
    {:ack, chk1_2} = TestThreePool.Server.workers!(:"second@127.0.0.1", @context, %{})

    {:ack, _details} = Noizu.MonitoringFramework.EnvironmentPool.Server.rebalance([:"first@127.0.0.1"], [:"first@127.0.0.1", :"second@127.0.0.1"], MapSet.new([TestPool, TestTwoPool, TestThreePool]), @context, %{sync: true})

    Process.sleep(2_000)
    # @TODO wait for server of last scheduled to transfer to change
# context = Noizu.ElixirCore.CallingContext.system(%{})
    {:ack, chk2_1} = TestThreePool.Server.workers!(:"first@127.0.0.1", @context, %{})
    {:ack, chk2_2} = TestThreePool.Server.workers!(:"second@127.0.0.1", @context, %{})

    delta1 = abs(length(chk1_1) - length(chk1_2))
    delta2 = abs(length(chk2_1) - length(chk2_2))

    assert delta1 > 50
    assert delta2 < 10

  end

  @tag capture_log: true
  test "server events" do
    #assert true == false
  end

  @tag capture_log: true
  test "server health_index" do
    #assert true == false
  end

end
