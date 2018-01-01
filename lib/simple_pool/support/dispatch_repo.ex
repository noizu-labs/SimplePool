#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.DispatchRepo do

  def new(ref, _context, options \\ %{}) do
    state = options[:state] || :new
    server = options[:server] || :pending
    lock = prepare_lock(options)
    %Noizu.SimplePool.DispatchEntity{identifier: ref, server: server, state: state, lock: lock}
  end

  def prepare_lock(options, force \\ false) do
    if options[:lock] || force do
      time = options[:time] || :os.system_time()
      lock_server = options[:lock][:server] || node()
      lock_process = options[:lock][:process] || self()
      lock_until = (options[:lock][:until]) || (options[:lock][:for] && :os.system_time(:seconds) + options[:lock][:for]) || (time + 600 + :rand.uniform(600))
      lock_type = options[:lock][:type] || :spawn
      {{lock_server, lock_process}, lock_type, lock_until}
    else
      nil
    end
  end

  def obtain_lock!(ref, context, options \\ %{lock: %{}}) do
    lock = {{lock_server, lock_process}, _lock_type, _lock_until} = prepare_lock(options, true)
    entity = get!(ref, context, options)
    time = options[:time] || :os.system_time()
    if entity do
      case entity.lock do
        nil -> {:ack, put_in(entity, [Access.key(:lock)], lock) |> update!(context, options)}
        {{s,p}, _lt, lu} ->
          cond do
            options[:force] -> {:ack, put_in(entity, [Access.key(:lock)], lock) |> update!(context, options)}
            time > lu -> {:ack, put_in(entity, [Access.key(:lock)], lock) |> update!(context, options)}
            s == lock_server and p == lock_process -> {:ack, put_in(entity, [Access.key(:lock)], lock) |> update!(context, options)}
            options[:conditional_checkout] ->

              check = case options[:conditional_checkout] do
                v when is_function(v) -> v.(entity)
                {m,f,1} -> apply(m, f, [entity])
                _ -> false
              end
              if check do
                {:ack, put_in(entity, [Access.key(:lock)], lock) |> update!(context, options)}
              else
                {:nack, {:locked, entity}}
              end
            true -> {:nack, {:locked, entity}}
          end
        _o -> {:nack, {:invalid, entity}}
      end
    else
      e = new(ref, context, options)
          |> put_in([Access.key(:lock)], lock)
          |> create!(context, options)
      {:ack, e}
    end
  end

  def release_lock!(ref, context, options \\ %{}) do
    time = options[:time] || :os.system_time()
      _lock = {{lock_server, lock_process}, lock_type, _lock_until} = prepare_lock(options, true)
    entity = get!(ref, context, options)
    if entity do
      case entity.lock do
        nil -> {:ack, entity}
        {{s,p}, lt, lu} ->
          cond do
            options[:force] ->
              {:ack, put_in(entity, [Access.key(:lock)], nil) |> update!(context, options)}
            time > lu ->
              {:ack, put_in(entity, [Access.key(:lock)], nil) |> update!(context, options)}
            s == lock_server and p == lock_process and lt == lock_type -> {:ack, put_in(entity, [Access.key(:lock)], nil) |> update!(context, options)}
            true -> {:nack, {:not_owned, entity}}
          end
      end
    else
      {:ack, nil}
    end
  end

  def workers!(host, service_entity, _context, options \\ %{}) do
    v = Noizu.SimplePool.Database.DispatchTable.match!([identifier: {:ref, service_entity, :_}, server: host])
        |> Amnesia.Selection.values
    {:ack, v}
  end

  #-------------------------
  #
  #-------------------------
  def get!(id, _context, _options \\ %{}) do
    id
    |> Noizu.SimplePool.Database.DispatchTable.read!()
    |> Noizu.ERP.entity()
  end

  def update!(entity, _context, options \\ %{}) do
    entity
    |> Noizu.ERP.record!(options)
    |> Noizu.SimplePool.Database.DispatchTable.write!()
    |> Noizu.ERP.entity()
  end

  def create!(entity, _context, options \\ %{}) do
    entity
    |> Noizu.ERP.record!(options)
    |> Noizu.SimplePool.Database.DispatchTable.write!()
    |> Noizu.ERP.entity()
  end

  def delete!(entity, _context, _options \\ %{}) do
    Noizu.SimplePool.Database.DispatchTable.delete!(entity.identifier)
    entity
  end

  #-------------------------
  #
  #-------------------------
  def get(id, _context, _options \\ %{}) do
    id
    |> Noizu.SimplePool.Database.DispatchTable.read()
    |> Noizu.ERP.entity()
  end

  def update(entity, _context, options \\ %{}) do
    entity
    |> Noizu.ERP.record(options)
    |> Noizu.SimplePool.Database.DispatchTable.write()
    |> Noizu.ERP.entity()
  end

  def create(entity, _context, options \\ %{}) do
    entity
    |> Noizu.ERP.record(options)
    |> Noizu.SimplePool.Database.DispatchTable.write()
    |> Noizu.ERP.entity()
  end

  def delete(entity, _context, _options \\ %{}) do
    Noizu.SimplePool.Database.DispatchTable.delete(entity.identifier)
    entity
  end
end