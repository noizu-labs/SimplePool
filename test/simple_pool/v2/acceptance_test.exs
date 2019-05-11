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
  test "basic_functionality - s_call!" do

    ref = Noizu.SimplePool.TestHelpers.unique_ref_v2(:two)

    # spawn
    Noizu.SimplePool.Support.TestV2TwoPool.Server.fetch(ref)
    assert Noizu.SimplePool.Support.TestV2TwoPool.Server.ping!(ref) == :pong

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
