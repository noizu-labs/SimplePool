#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2022 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule Noizu.SimplePool.Telemetry do
  require Logger

  defp obtain_semaphore(key, count \\ 1) do
    try do
      Semaphore.acquire(key, count)
    rescue _e -> false
    catch _e -> false
    end
  end

  def worker_init_span(base, ref, block, context) do
    br = :os.system_time(:millisecond)
    response = block.()
    ar = :os.system_time(:millisecond)
    td = ar - br
    cond do
      td > 450 -> rate_limited_log(base, :profile, :worker_init, :very_high, context)  && Logger.error(fn -> {base.banner("[Reg Time] - Critical #{__MODULE__} (#{inspect Noizu.ERP.sref(ref) } = #{td} milliseconds"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
      td > 250 -> rate_limited_log(base, :profile, :worker_init, :high, context)  && Logger.warn(fn -> {base.banner("[Reg Time] - Critical #{__MODULE__} (#{inspect Noizu.ERP.sref(ref) } = #{td} milliseconds"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
      :else -> :ok
    end
    response
  end

  def rate_limited_log(mod, action, event, params, context, options \\ [], delay \\ 15_000, frequency \\ 5)
  def rate_limited_log(mod, action, event, call, _context, options, delay, frequency) do
    cond do
      options[:trace] -> true
      :else ->
        key = case call do
                c when is_atom(c) -> {mod, action, event, c}
                {d, {_, _}, {t, c, _}} when is_atom(d) and is_atom(t) and is_atom(c) -> {mod, action, event,  c}
                {d, {_, _}, {t, c, _}} when is_atom(d) and is_atom(t) and is_tuple(c) -> {mod, action, event,  elem(c, 0)}
                {t, c, _} when is_atom(t) and is_atom(c) -> {mod, action, event,  c}
                {t, c, _} when is_atom(t) and is_tuple(c) -> {mod, action, event, elem(c, 0)}
                _ -> {mod, action, event, :other}
              end
        cond do
          obtain_semaphore(key, frequency) ->
            spawn(fn -> Process.sleep(delay) && Semaphore.release(key) end)
            true
          :else -> false
        end
    end
  end

end

