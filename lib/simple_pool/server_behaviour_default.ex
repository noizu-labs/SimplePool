#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.ServerBehaviourDefault do
  alias Noizu.SimplePool.Worker.Link
  require Logger

  def verbose(verbose, base) do
    if verbose == :auto do
      if Application.get_env(:noizu_simple_pool, base, %{})[:PoolSupervisor][:verbose] do
        Application.get_env(:noizu_simple_pool, base, %{})[:PoolSupervisor][:verbose]
      else
        Application.get_env(:noizu_simple_pool, :verbose, false)
      end
    else
      verbose
    end
  end

  def run_on_host(mod, _base, worker_lookup_handler, ref, {m,f,a}, context, options \\ %{}, timeout \\ 30_000) do
    case worker_lookup_handler.host!(ref, mod, context, options) do
      {:ack, host} ->
        if host == node() do
          apply(m,f,a)
        else
          :rpc.call(host, m,f,a, timeout)
        end
      o -> o
    end
  end

  def cast_to_host(mod, _base, worker_lookup_handler, ref, {m,f,a}, context, options) do
    case worker_lookup_handler.host!(ref, mod, context, options) do
      {:ack, host} ->
        if host == node() do
          apply(m,f,a)
        else
          :rpc.cast(host, m,f,a)
        end
      o ->
        o
    end
  end

  #-------------------------------------------------------------------------
  # bulk_migrate!
  #-------------------------------------------------------------------------
  def bulk_migrate!(mod, transfer_server, context, options) do
    tasks = if options[:sync] do
      to = options[:timeout] || 60_000
      options_b = put_in(options, [:timeout], to)

      Task.async_stream(transfer_server, fn({server, refs}) ->
                                           o = Task.async_stream(refs, fn(ref) ->
                                                                         {ref, mod.o_call(ref, {:migrate!, ref, server, options_b}, context, options_b, to)}
                                           end, timeout: to)
                                           {server, o |> Enum.to_list()}
      end, timeout: to)
    else
      to = options[:timeout] || 60_000
      options_b = put_in(options, [:timeout], to)
      Task.async_stream(transfer_server, fn({server, refs}) ->
                                           o = Task.async_stream(refs, fn(ref) ->
                                                                         {ref, mod.o_cast(ref, {:migrate!, ref, server, options_b}, context)}
                                           end, timeout: to)
                                           {server, o |> Enum.to_list()}
      end, timeout: to)
    end

    r = Enum.reduce(tasks, %{}, fn(task_outcome, acc) ->
      case task_outcome do
        {:ok, {server, outcome}} ->
          put_in(acc, [server], outcome)
        _error -> acc
      end
    end)

    {:ack, r}
  end

  #-------------------------------------------------------------------------
  # get_direct_link!
  #-------------------------------------------------------------------------
  def get_direct_link!(mod, ref, context, options \\ %{spawn: false}) do
    case  mod.worker_ref!(ref, context) do
      nil ->
        %Link{ref: ref, handler: mod, handle: nil, state: {:error, :no_ref}}
      {:error, details} ->
        %Link{ref: ref, handler: mod, handle: nil, state: {:error, details}}
      ref ->
        options_b = if Map.has_key?(options, :spawn) do
          options
        else
          put_in(options, [:spawn], false)
        end

        case mod.worker_pid!(ref, context, options_b) do
          {:ack, pid} ->
            %Link{ref: ref, handler: mod, handle: pid, state: :valid}
          {:error, details} ->
            %Link{ref: ref, handler: mod, handle: nil, state: {:error, details}}
          error ->
            %Link{ref: ref, handler: mod, handle: nil, state: {:error, error}}
        end
    end
  end


  #-------------------------------------------------------------------------
  # s_call unsafe implementations
  #-------------------------------------------------------------------------
  def s_call_unsafe(mod, ref, extended_call, context, options, timeout) do
    timeout = options[:timeout] || timeout
    case mod.worker_pid!(ref, context, options) do
      {:ack, pid} ->
        case GenServer.call(pid, extended_call, timeout) do
          :s_retry ->
            case mod.worker_pid!(ref, context, options) do
              {:ack, pid} ->
                GenServer.call(pid, extended_call, timeout)
              error -> error
            end
          v -> v
        end
      error ->
        error
    end # end case
  end #end s_call_unsafe

  def s_cast_unsafe(mod, ref, extended_call, context, options) do
    case mod.worker_pid!(ref, context, options) do
      {:ack, pid} -> GenServer.cast(pid, extended_call)
      error ->
        error
    end
  end


  def crash_protection_rs_call!({mod, base, worker_lookup_handler, s_redirect_feature, log_timeout}, identifier, call, context, options, timeout) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_call!, {mod, identifier, timeout}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_call_unsafe(identifier, extended_call, context, options, timeout)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: timeout, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call! - timeout.\n call: #{inspect extended_call}") end
              end
              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do

              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call! - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              end
              {:error, {:exit, o}}
            catch
              :exit, e ->
                {:error, {:exit, e}}
            end # end inner try
        end
    end # end try
  end

  @doc """
    Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
  """
  def crash_protection_s_call!(mod, identifier, call, context , options, timeout) do
    case mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        try do
          options_b = put_in(options, [:spawn], true)
          mod.run_on_host(ref, {mod, :rs_call!, [ref, call, context, options_b, timeout]}, context, options_b, timeout)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end # end s_call!

  def crash_protection_rs_cast!({mod, base, worker_lookup_handler, s_redirect_feature, log_timeout}, identifier, call, context, options) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast!, {mod, identifier}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_cast_unsafe(identifier, extended_call, context, options)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: c, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_cast! - timeout.\n call: #{inspect extended_call}") end

              end
              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_cast! - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              end

              {:error, {:exit, o}}
            catch
              :exit, e ->
                {:error, {:exit, e}}
            end # end inner try
        end
    end # end try
  end

  @doc """
    Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
  """
  def crash_protection_s_cast!(mod, identifier, call, context, options) do
    case  mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        try do
          options_b = put_in(options, [:spawn], true)
          mod.cast_to_host(ref, {mod, :rs_cast!, [ref, call, context, options_b]}, context, options_b)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end # end s_cast!

  def crash_protection_rs_call({mod, base, worker_lookup_handler, s_redirect_feature, log_timeout}, identifier, call, context, options, timeout) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_call, {mod, identifier, timeout}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_call_unsafe(identifier, extended_call, context, options, timeout)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: timeout, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call - timeout.\n call: #{inspect extended_call}") end
              end

              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              end
              {:error, {:exit, o}}
            catch
              :exit, e ->
                {:error, {:exit, e}}
            end # end inner try
        end
    end # end try
  end

  @doc """
    Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
  """
  def crash_protection_s_call(mod, identifier, call, context, options, timeout) do
    case  mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        try do
          options_b = put_in(options, [:spawn], false)
          mod.run_on_host(ref, {mod, :rs_call, [ref, call, context, options_b, timeout]}, context, options_b, timeout)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end # end s_call!

  def crash_protection_rs_cast({mod, base, worker_lookup_handler, s_redirect_feature, log_timeout}, identifier, call, context, options) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast, {mod, identifier}, {:s, call, context}}, else: {:s, call, context}
    try do
      mod.s_cast_unsafe(identifier, extended_call, context, options)
    catch
      :exit, e ->
        case e do
          {:timeout, c} ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :timeout, %{timeout: c, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call! - timeout.\n call: #{inspect extended_call}") end
              end
              {:error, {:timeout, c}}
            catch
              :exit, e ->  {:error, {:exit, e}}
            end # end inner try
          o  ->
            try do
              if log_timeout do
                worker_lookup_handler.record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
              else
                Logger.warn fn -> base.banner("#{mod}.s_call! - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
              end
              {:error, {:exit, o}}
            catch
              :exit, e ->
                {:error, {:exit, e}}
            end # end inner try
        end
    end # end try
  end

  @doc """
    Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
  """
  def crash_protection_s_cast(mod, identifier, call, context, options) do
    case  mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        try do
          options_b = put_in(options, [:spawn], false)
          mod.cast_to_host(ref, {mod, :rs_cast, [ref, call, context, options_b]}, context, options_b)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end # end s_cast!



  @doc """
    Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
  """
  def nocrash_protection_s_call!({mod, s_redirect_feature}, identifier, call, context, options, timeout ) do
    case mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_call!, {mod, ref, timeout}, {:s, call, context}}, else: {:s, call, context}
        options_b = put_in(options, [:spawn], true)
        mod.run_on_host(ref, {mod, :s_call_unsafe, [ref, extended_call, context, options_b, timeout]}, context, options_b, timeout)
    end
  end # end s_call!

  @doc """
    Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Spawn worker if not currently active.
  """
  def nocrash_protection_s_cast!({mod, s_redirect_feature}, identifier, call, context, options) do
    case mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast!, {mod, ref}, {:s, call, context}}, else: {:s, call, context}
        options_b = put_in(options, [:spawn], true)
        mod.cast_to_host(ref, {__MODULE__, :s_cast_unsafe, [ref, extended_call, context, options_b]}, context, options_b)
    end # end case worker_ref!
  end # end s_cast!

  @doc """
    Forward a call to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
  """
  def nocrash_protection_s_call({mod, s_redirect_feature}, identifier, call, context, options, timeout ) do
    case  mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_call, {mod, ref, timeout}, {:s, call, context}}, else: {:s, call, context}
        options_b = put_in(options, [:spawn], false)
        mod.run_on_host(ref, {__MODULE__, :s_call_unsafe, [ref, extended_call, context, options_b, timeout]}, context, options_b, timeout)
    end # end case
  end # end s_call!

  @doc """
    Forward a cast to appopriate worker, along with delivery redirect details if s_redirect enabled. Do not spawn worker if not currently active.
  """
  def nocrash_protection_s_cast({mod, s_redirect_feature}, identifier, call, context, options) do
    case mod.worker_ref!(identifier, context) do
      {:error, details} -> {:error, details}
      ref ->
        extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast, {mod, ref}, {:s, call, context}}, else: {:s, call, context}
        options_b = put_in(options, [:spawn], false)
        mod.cast_to_host(ref, {__MODULE__, :s_cast_unsafe, [ref, extended_call, context, options_b]}, context, options_b)
    end # end case worker_ref!
  end # end s_cast!


  @doc """
    Crash Protection always enabled, for now.
    @TODO links should be allowed in place of refs.
    @TODO forward should handle cast, call and info forwarding
  """
  def link_forward!({mod, base, s_redirect_feature}, %Link{} = link, call, context, options) do
    extended_call = if (options[:redirect] || s_redirect_feature), do: {:s_cast, {mod, link.ref}, {:s, call, context}}, else: {:s, call, context}
    now_ts = options[:time] || :os.system_time(:seconds)
    options_b = options #put_in(options, [:spawn], true)

    try do
      if link.handle && (link.expire == :infinity or link.expire > now_ts) do
        GenServer.cast(link.handle, extended_call)
        {:ok, link}
      else
        case mod.worker_pid!(link.ref, context, options_b) do
          {:ack, pid} ->
            GenServer.cast(pid, extended_call)
            rc = if link.update_after == :infinity, do: :infinity, else: now_ts + link.update_after + :rand.uniform(div(link.update_after, 2))
            {:ok, %Link{link| handle: pid, state: :valid, expire: rc}}
          {:nack, details} -> {:error, %Link{link| handle: nil, state: {:error, {:nack, details}}}}
          {:error, details} ->
            {:error, %Link{link| handle: nil, state: {:error, details}}}
          error ->
            {:error, %Link{link| handle: nil, state: {:error, error}}}
        end # end case worker_pid!
      end # end if else
    catch
      :exit, e ->
        try do
          Logger.warn(fn -> {base.banner("#{__MODULE__}.s_forward - dead worker (#{inspect link})\n\n"),  Noizu.ElixirCore.CallingContext.metadata(context)} end )
          {:error, %Link{link| handle: nil, state: {:error, {:exit, e}}}}
        catch
          :exit, e ->
            {:error, %Link{link| handle: nil, state: {:error, {:exit, e}}}}
        end # end inner try
      e -> {:error, %Link{link| handle: nil, state: {:error, {:exit, e}}}}
    end # end try
  end # end link_forward!

  def definition(type, base, server, pool) do
    case type do
      :auto ->
        a = %Noizu.SimplePool.MonitoringFramework.Service.Definition{
          identifier: {node(), base},
          server: node(),
          pool: server,
          supervisor: pool,
          time_stamp: DateTime.utc_now(),
          hard_limit: 0,
          soft_limit: 0,
          target: 0,
        }
        Application.get_env(:noizu_simple_pool, :definitions, %{})[base] || a
      v -> v
    end
  end

end
