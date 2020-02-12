#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2020 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Test.NmidGenerator do
  def generate(_seq, _opts) do
    :os.system_time(:micro_seconds)
  end
  def generate!(seq, opts) do
    generate(seq, opts)
  end
end

