defmodule Noizu.SimplePool.BasicTest do
  use ExUnit.Case

  @context Noizu.ElixirCore.CallingContext.system(%{})

  test "basic_functionality - s_call!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.test_s_call!(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_call!] == :bannana
  end

  test "basic_functionality - s_cast!" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.test_s_cast!(ref, :apple, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_cast!] == :apple
  end


  test "basic_functionality - s_call" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.test_s_call(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_call] == nil

    Noizu.SimplePool.Support.TestPool.Server.test_s_call(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_call] == :bannana
  end


  test "basic_functionality - s_cast" do
    ref = Noizu.SimplePool.TestHelpers.unique_ref()
    Noizu.SimplePool.Support.TestPool.Server.test_s_cast(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_cast] == nil

    Noizu.SimplePool.Support.TestPool.Server.test_s_cast(ref, :bannana, @context)
    sut = Noizu.SimplePool.Support.TestPool.Server.fetch(ref, :default, @context)
    assert sut.data[:s_cast] == :bannana
  end


end
