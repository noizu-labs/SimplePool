#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

# @todo should be renamed Default and moved into behaviour definition for consistency.
defmodule Noizu.SimplePool.V2.Router.RouterProvider do
  @moduledoc """
    Provides implementation for currently supported router call variations,
    s_call with crash protection, s_call with crash protection off, etc.
    @todo need 3 argument host! method(drop server argument since we should know it already).
    @todo change worker_pid! to pid! (either the calls should all be prefixed with worker_ or the prefix should be removed).
  """
  alias Noizu.SimplePool.Worker.Link
  require Logger
  @default_timeout 30_000

  @doc """
    Run a function(mfa) on the host responsible for the specified ref.

    If already on the host apply will be used, otherwise an :rpc.call will be made to execute the method remotely.
  """
  def run_on_host(pool_server, ref, {m, f, a}, context, options \\ nil, timeout \\ 30_000) do
    case pool_server.worker_management().host!(ref, context, options) do
      {:ack, host} ->
        if host == node() do
          apply(m,f,a)
        else
          :rpc.call(host, m,f,a, timeout)
        end
      o -> o
    end
  end

  @doc """
    Run a function(mfa) on the host responsible for the specified ref with out waiting for the response.

    If already on the host a process will be spawned and apply called,
    otherwise an :rpc.cast will be made to execute the method remotely.
  """
  def cast_to_host(pool_server, ref, {m, f, a}, context, options \\ nil) do
    case pool_server.worker_management().host!(ref, context, options) do
      {:ack, host} ->
        if host == node() do
          spawn fn -> apply(m,f,a) end
          :ok
        else
          :rpc.cast(host, m,f,a)
        end
      o -> o
    end
  end

  #---------------------------------------------
  # s_*_unsafe
  #---------------------------------------------
  @doc """
    Perform a bare s_call with out exception handling.
  """
  def s_call_unsafe(pool_server, ref, extended_call, context, options, timeout) do
    timeout = options[:timeout] || timeout
    case pool_server.worker_management().process!(ref, context, options) do
      {:ack, pid} ->
        case GenServer.call(pid, extended_call, timeout) do
          :s_retry ->
            case pool_server.worker_management().process!(ref, context, options) do
              {:ack, pid} ->
                GenServer.call(pid, extended_call, timeout)
              error -> error
            end
          response -> response
        end
      error -> error
    end # end case
  end

  @doc """
    Perform a bare s_cast with out exception handling.
  """
  def s_cast_unsafe(pool_server, ref, extended_call, context, options) do
    case pool_server.worker_management().process!(ref, context, options) do
      {:ack, pid} -> GenServer.cast(pid, extended_call)
      error -> error
    end
  end


  #---------------------------------------------
  # s_*_crash_protection
  #---------------------------------------------

  @doc """
    Forward a call to appropriate worker. Spawn worker if not currently active.
  """
  def s_call_crash_protection!(pool_server, identifier, call, context, options \\ nil, timeout \\ nil) do
    timeout = timeout || 30_000 #@TODO final logic
    case pool_server.worker_management().worker_ref!(identifier, context) do
      e = {:error, _details} -> e
      ref ->
        try do
          options_b = put_in(options || %{}, [:spawn], true)
          m = pool_server.router()
          f = :rs_call!
          a = [ref, call, context, options_b, timeout]
          pool_server.router().run_on_host(ref, {m, f, a}, context, options_b, timeout)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end

  @doc """
    Version of s_call! that will be invoked on a worker process' host node.
  """
  def rs_call_crash_protection!(pool_server, identifier, call, context, options \\ nil, timeout \\ nil) do
    extended_call = pool_server.router().extended_call(:s_call!, identifier, call, context, options, timeout)
    try do
      pool_server.router().s_call_unsafe(identifier, extended_call, context, options, timeout)
    catch
      :rescue, e -> handle_s_exception(e, :s_call!, pool_server, identifier, extended_call, timeout, context, options)
      :exit, e -> handle_s_exception(e, :s_call!, pool_server, identifier, extended_call, timeout, context, options)
    end # end try
  end

  def s_call_crash_protection(pool_server, identifier, call, context, options \\ nil, timeout \\ nil) do
    case pool_server.worker_management().worker_ref!(identifier, context) do
      e = {:error, _details} -> e
      ref ->
        try do
          options_b = put_in(options || %{}, [:spawn], false)
          m = pool_server.router()
          f = :rs_call
          a = [ref, call, context, options_b, timeout]
          pool_server.router().run_on_host(ref, {m, f, a}, context, options_b, timeout)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end

  def rs_call_crash_protection(pool_server, identifier, call, context, options \\ nil, timeout \\ nil) do
    extended_call = pool_server.router().extended_call(:s_call, identifier, call, context, options, timeout)
    try do
      pool_server.router().s_call_unsafe(identifier, extended_call, context, options, timeout)
    catch
      :rescue, e -> handle_s_exception(e, :s_call, pool_server, identifier, extended_call, timeout, context, options)
      :exit, e -> handle_s_exception(e, :s_call, pool_server, identifier, extended_call, timeout, context, options)
    end # end try
  end

  def s_cast_crash_protection!(pool_server, identifier, call, context, options \\ nil) do
    case pool_server.worker_management().worker_ref!(identifier, context) do
      e = {:error, _details} -> e
      ref ->
        try do
          options_b = put_in(options || %{}, [:spawn], true)
          m = pool_server.router()
          f = :rs_cast!
          a = [ref, call, context, options_b]
          pool_server.router().cast_to_host(ref, {m, f, a}, context, options_b)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end

  def rs_cast_crash_protection!(pool_server, identifier, call, context, options \\ nil) do
    timeout = nil
    extended_call = pool_server.router().extended_call(:s_cast!, identifier, call, context, options, timeout)
    try do
      pool_server.router().s_cast_unsafe(identifier, extended_call, context, options)
    catch
      :rescue, e -> handle_s_exception(e, :s_cast!, pool_server, identifier, extended_call, timeout, context, options)
      :exit, e -> handle_s_exception(e, :s_cast!, pool_server, identifier, extended_call, timeout, context, options)
    end # end try
  end

  def s_cast_crash_protection(pool_server, identifier, call, context, options \\ nil) do
    case pool_server.worker_management().worker_ref!(identifier, context) do
      e = {:error, _details} -> e
      ref ->
        try do
          options_b = put_in(options || %{}, [:spawn], false)
          m = pool_server.router()
          f = :rs_cast!
          a = [ref, call, context, options_b]
          pool_server.router().cast_to_host(ref, {m, f, a}, context, options_b)
        catch
          :exit, e -> {:error, {:exit, e}}
        end
    end
  end

  def rs_cast_crash_protection(pool_server, identifier, call, context, options \\ nil) do
    timeout = nil
    extended_call = pool_server.router().extended_call(:s_cast, identifier, call, context, options, timeout)
    try do
      pool_server.router().s_cast_unsafe(identifier, extended_call, context, options)
    catch
      :rescue, e -> handle_s_exception(e, :s_cast, pool_server, identifier, extended_call, timeout, context, options)
      :exit, e -> handle_s_exception(e, :s_cast, pool_server, identifier, extended_call, timeout, context, options)
    end # end try
  end

  #---------------------------------------------
  # s_*_no_crash_protection
  #---------------------------------------------

  @doc """
    Forward a call to appropriate worker. Spawn worker if not currently active.
  """
  def s_call_no_crash_protection!(pool_server, identifier, call, context, options \\ nil, timeout \\ nil) do
    case pool_server.worker_management().worker_ref!(identifier, context) do
      e = {:error, _details} -> e
      ref ->
        options_b = put_in(options || %{}, [:spawn], true)
        m = pool_server.router()
        f = :rs_call!
        a = [ref, call, context, options_b, timeout]
        pool_server.router().run_on_host(ref, {m, f, a}, context, options_b, timeout)
    end
  end

  @doc """
    Version of s_call! that will be invoked on a worker process' host node.
  """
  def rs_call_no_crash_protection!(pool_server, identifier, call, context, options \\ nil, timeout \\ nil) do
    extended_call = pool_server.router().extended_call(:s_call!, identifier, call, context, options, timeout)
    pool_server.router().s_call_unsafe(identifier, extended_call, context, options, timeout)
  end

  def s_call_no_crash_protection(pool_server, identifier, call, context, options \\ nil, timeout \\ nil) do
    case pool_server.worker_management().worker_ref!(identifier, context) do
      e = {:error, _details} -> e
      ref ->
        options_b = put_in(options || %{}, [:spawn], false)
        m = pool_server.router()
        f = :rs_call
        a = [ref, call, context, options_b, timeout]
        pool_server.router().run_on_host(ref, {m, f, a}, context, options_b, timeout)
    end
  end

  def rs_call_no_crash_protection(pool_server, identifier, call, context, options \\ nil, timeout \\ nil) do
    extended_call = pool_server.router().extended_call(:s_call, identifier, call, context, options, timeout)
    pool_server.router().s_call_unsafe(identifier, extended_call, context, options, timeout)
  end

  def s_cast_no_crash_protection!(pool_server, identifier, call, context, options \\ nil) do
    case pool_server.worker_management().worker_ref!(identifier, context) do
      e = {:error, _details} -> e
      ref ->
        options_b = put_in(options || %{}, [:spawn], true)
        m = pool_server.router()
        f = :rs_cast!
        a = [ref, call, context, options_b]
        pool_server.router().cast_to_host(ref, {m, f, a}, context, options_b)
    end
  end

  def rs_cast_no_crash_protection!(pool_server, identifier, call, context, options \\ nil) do
    timeout = nil
    extended_call = pool_server.router().extended_call(:s_cast!, identifier, call, context, options, timeout)
    pool_server.router().s_cast_unsafe(identifier, extended_call, context, options)
  end

  def s_cast_no_crash_protection(pool_server, identifier, call, context, options \\ nil) do
    case pool_server.worker_management().worker_ref!(identifier, context) do
      e = {:error, _details} -> e
      ref ->
        options_b = put_in(options || %{}, [:spawn], false)
        m = pool_server.router()
        f = :rs_cast!
        a = [ref, call, context, options_b]
        pool_server.router().cast_to_host(ref, {m, f, a}, context, options_b)
    end
  end

  def rs_cast_no_crash_protection(pool_server, identifier, call, context, options \\ nil) do
    timeout = nil
    extended_call = pool_server.router().extended_call(:s_cast, identifier, call, context, options, timeout)
    pool_server.router().s_cast_unsafe(identifier, extended_call, context, options)
  end

  #----------------------------------------
  # extended calls
  #----------------------------------------
  def extended_call_with_redirect_support(pool_server, s_type, ref, call, context, _options, timeout \\ nil) do
    msg_prefix = case s_type do
      # Standard Message
      :s_call! -> :s
      :s_call -> :s
      :s_cast! -> :s
      :s_cast -> :s

      # System Message
      :m_call! -> :m
      :m_call -> :m
      :m_cast! -> :m
      :m_cast -> :m

      # Internal Message (Self Messaging)
      :i_call! -> :i
      :i_call -> :i
      :i_cast! -> :i
      :i_cast -> :i

      _ -> throw "Unsupported message type: #{inspect s_type}"
    end
    {:msg_envelope, {pool_server.pool_worker(), {s_type, ref, timeout}}, {msg_prefix, call, context}}
  end

  def extended_call_without_redirect_support(_pool_server, s_type, _ref, call, context, _options, _timeout \\ nil) do
    msg_prefix = case s_type do
      # Standard Message
      :s_call! -> :s
      :s_call -> :s
      :s_cast! -> :s
      :s_cast -> :s

      # System Message
      :m_call! -> :m
      :m_call -> :m
      :m_cast! -> :m
      :m_cast -> :m

      # Internal Message (Self Messaging)
      :i_call! -> :i
      :i_call -> :i
      :i_cast! -> :i
      :i_cast -> :i

      _ -> throw "Unsupported message type: #{inspect s_type}"
    end
    {msg_prefix, call, context}
  end



  #----------------------------------------
  #
  #----------------------------------------

  def self_call(pool_server, call, context \\ nil, options \\ nil) do
    # note, we leave out some of the complexity from the V1 implementation, which verifies that a given node
    # supports the pool service we represent.
    extended_call = {:s, call, context}
    timeout = options[:timeout] || pool_server.router().option(:defaul_timeout, @default_timeout)
    GenServer.call(pool_server, extended_call, timeout)
  end

  def self_cast(pool_server, call, context \\ nil, _options \\ nil) do
    # note, we leave out some of the complexity from the V1 implementation, which verifies that a given node
    # supports the pool service we represent.
    extended_call = {:s, call, context}
    #timeout = options[:timeout] || pool_server.router().option(:defaul_timeout, @default_timeout)
    GenServer.cast(pool_server, extended_call)
  end

  #----------------------------------------
  #
  #----------------------------------------
  #----------------------------------------
  #
  #----------------------------------------
  def internal_system_call(pool_server, call, context \\ nil, options \\ nil) do
    extended_call = {:m, call, context}
    timeout = options[:timeout] || pool_server.router().option(:defaul_timeout, @default_timeout)
    GenServer.call(pool_server, extended_call, timeout)
  end

  def internal_system_cast(pool_server, call, context \\ nil, _options \\ nil) do
    extended_call = {:m, call, context}
    GenServer.cast(pool_server, extended_call)
  end

  #----------------------------------------
  #
  #----------------------------------------
  def remote_system_call(pool_server, remote_node, call, context \\ nil, options \\ nil) do
    extended_call = {:m, call, context}
    timeout = options[:timeout] || pool_server.router().option(:defaul_timeout, @default_timeout)
    if (remote_node == node()) do
      GenServer.call(pool_server, extended_call, timeout)
    else
      GenServer.call({pool_server, remote_node}, extended_call, timeout)
    end
  end

  def remote_system_cast(pool_server, remote_node, call, context \\ nil, _options \\ nil) do
    extended_call = {:m, call, context}
    if (remote_node == node()) do
      GenServer.cast(pool_server, extended_call)
    else
      GenServer.cast({pool_server, remote_node}, extended_call)
    end
  end

  #----------------------------------------
  #
  #----------------------------------------
  def internal_call(pool_server, call, context \\ nil, options \\ nil) do
    extended_call = {:i, call, context}
    timeout = options[:timeout] || pool_server.router().option(:defaul_timeout, @default_timeout)
    GenServer.call(pool_server, extended_call, timeout)
  end

  def internal_cast(pool_server, call, context \\ nil, _options \\ nil) do
    extended_call = {:i, call, context}
    GenServer.cast(pool_server, extended_call)
  end

  #----------------------------------------
  #
  #----------------------------------------
  def remote_call(pool_server, remote_node, call, context \\ nil, options \\ nil) do
    extended_call = {:i, call, context}
    timeout = options[:timeout] || pool_server.router().option(:defaul_timeout, @default_timeout)
    if (remote_node == node()) do
      GenServer.call(pool_server, extended_call, timeout)
    else
      GenServer.call({pool_server, remote_node}, extended_call, timeout)
    end
  end

  def remote_cast(pool_server, remote_node, call, context \\ nil, _options \\ nil) do
    extended_call = {:i, call, context}
    if (remote_node == node()) do
      GenServer.cast(pool_server, extended_call)
    else
      GenServer.cast({pool_server, remote_node}, extended_call)
    end
  end

  #----------------------------------------
  #
  #----------------------------------------
  def link_forward!(pool_server, %Link{} = link, call, context, options \\ nil) do
    timeout = nil
    extended_call = pool_server.router().extended_call(:s_cast, link.ref, call, context, options, timeout)
    now_ts = options[:time] || :os.system_time(:seconds)
    options_b = options #put_in(options, [:spawn], true)
    try do
      if link.handle && (link.expire == :infinity or link.expire > now_ts) do
        GenServer.cast(link.handle, extended_call)
        {:ok, link}
      else
        case pool_server.worker_management().process!(link.ref, context, options_b) do
          {:ack, pid} ->
            GenServer.cast(pid, extended_call)
            rc = if link.update_after == :infinity, do: :infinity, else: now_ts + link.update_after + :rand.uniform(div(link.update_after, 2))
            {:ok, %Link{link| handle: pid, state: :valid, expire: rc}}
          {:nack, details} -> {:error, %Link{link| handle: nil, state: {:error, {:nack, details}}}}
          {:error, details} -> {:error, %Link{link| handle: nil, state: {:error, details}}}
          error -> {:error, %Link{link| handle: nil, state: {:error, error}}}
        end # end case process!
      end # end if else
    catch
      :rescue, e ->
        handle_s_exception(e, :link_forward!, pool_server, link.ref, extended_call, timeout, context, options)
        {:error, %Link{link| handle: nil, state: {:error, {:exit, e}}}}
      :exit, e ->
        handle_s_exception(e, :link_forward!, pool_server, link.ref, extended_call, timeout, context, options)
        {:error, %Link{link| handle: nil, state: {:error, {:exit, e}}}}
    end # end try
  end

  #----------------------------------------
  #
  #----------------------------------------
  def get_direct_link!(pool_server, ref, context, options \\ %{}) do
    options = options || %{}
    case pool_server.pool_worker_entity().__struct__.ref(ref) do
      nil ->
        %Link{ref: ref, handler: pool_server, handle: nil, state: {:error, :no_ref}}
      {:error, details} ->
        %Link{ref: ref, handler: pool_server, handle: nil, state: {:error, details}}
      ref ->
        options_b = cond do
          Map.has_key?(options, :spawn) -> options
          true -> put_in(options, [:spawn], false)
        end
        case pool_server.worker_management().process!(ref, context, options_b) do
          {:ack, pid} -> %Link{ref: ref, handler: pool_server, handle: pid, state: :valid}
          {:error, details} -> %Link{ref: ref, handler: pool_server, handle: nil, state: {:error, details}}
          error -> %Link{ref: ref, handler: pool_server, handle: nil, state: {:error, error}}
        end
    end
  end

  #----------------------------------------
  #
  #----------------------------------------
  #def route_call(pool_server, envelope, from, state) do
  #  Logger.info("WIP - route_call #{inspect envelope}")
  #  throw :pri0_route_call
  #end

  #def route_cast(pool_server, envelope, state) do
  #  Logger.info("WIP - route_cast #{inspect envelope}")
  #  throw :pri0_route_cast
  #end

  #def route_info(pool_server, envelope, state) do
  #  Logger.info("WIP - route_info #{inspect envelope}")
  #  throw :pri0_route_info
  #end

  #----------------------------------------
  #
  #----------------------------------------
  defp handle_s_exception(exception, s_type, pool_server, identifier, extended_call, timeout, context, options) do
    case exception do
      {:timeout, c} ->
        try do
          Logger.warn fn -> pool_server.banner("#{pool_server}.#{s_type} - timeout.\n call: #{inspect extended_call}") end
          if pool_server.router().option(:record_timeout, false) == true do
            pool_server.worker_management().record_event!(identifier, :timeout, %{timeout: timeout, call: extended_call}, context, options)
          end
          {:error, {:timeout, c}}
        catch
          :exit, e ->  {:error, {:exit, e}}
        end # end inner try
      o  ->
        try do
          Logger.warn fn -> pool_server.banner("#{pool_server}.#{s_type} - exit raised.\n call: #{inspect extended_call}\nraise: #{inspect o}") end
          if pool_server.router().option(:record_timeout, false) == true do
            pool_server.worker_management().record_event!(identifier, :exit, %{exit: o, call: extended_call}, context, options)
          end
          {:error, {:exit, o}}
        catch
          :exit, e ->
            {:error, {:exit, e}}
        end # end inner try
    end
  end

end