#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2022 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule Noizu.SimplePool.Telemetry do
  require Logger

  def worker_init_span(base, ref, block, context) do
    br = :os.system_time(:millisecond)
    response = block.()
    ar = :os.system_time(:millisecond)
    td = ar - br
    cond do
      td > 450 -> Logger.error(fn -> {base.banner("[Reg Time] - Critical #{__MODULE__} (#{inspect Noizu.ERP.sref(ref) } = #{td} milliseconds"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
      td > 250 -> Logger.warn(fn -> {base.banner("[Reg Time] - Delayed #{__MODULE__} (#{inspect Noizu.ERP.sref(ref) } = #{td} milliseconds"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
      :else -> :ok
    end
    response
  end

end

