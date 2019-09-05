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
  test "basic_functionality - fetch" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    f = Noizu.SimplePool.Support.TestV2Pool.Server.fetch!(ref, :state)
    assert f.worker_ref == ref

    {pid, host} = Noizu.SimplePool.Support.TestV2Pool.Server.fetch!(ref, :process)
    assert host == :"first@127.0.0.1"
    p_info = Process.info(pid)
    assert p_info[:dictionary][:"$initial_call"] == {Noizu.SimplePool.Support.TestV2Pool.Worker, :init, 1}
  end

  @tag :v2
  test "basic_functionality - ping!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:one)
    Noizu.SimplePool.Support.TestV2Pool.Server.fetch!(ref)
    assert Noizu.SimplePool.Support.TestV2Pool.Server.ping(ref) == :pong
  end

  @tag :v2
  test "basic_functionality - s_call!" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - s_cast!" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - s_call" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - s_cast" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality fetch process" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality fetch state" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality fetch default" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality kill process" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality crash process" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality health check - healthy" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality ping worker" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - get_direct_link" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - link_forward!" do
    :wip
  end

  @tag :v2
  @tag capture_log: true
  test "basic_functionality - link_forward! - does not auto start" do
    :wip
  end

end
