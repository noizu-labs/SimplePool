#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Support.TopologyProvider do
  @behaviour Noizu.MnesiaVersioning.TopologyBehaviour

  def mnesia_nodes() do
    {:ok, [node()]}
  end

  def database() do
    [Noizu.SimplePool.Database]
  end
end
