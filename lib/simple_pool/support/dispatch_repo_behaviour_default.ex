#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.DispatchRepoBehaviourDefault do
  use Amnesia

  def new(mod, ref, _context, options \\ %{}) do
    state = options[:state] || :new
    server = options[:server] || :pending
    lock = mod.prepare_lock(options)
    %Noizu.SimplePool.DispatchEntity{identifier: ref, server: server, state: state, lock: lock}
  end

  def prepare_lock(options, force \\ false) do
    if options[:lock] || force do
      time = options[:time] || :os.system_time()
      lock_server = options[:lock][:server] || node()
      lock_process = options[:lock][:process] || self()
      lock_until = (options[:lock][:until]) || (options[:lock][:for] && :os.system_time(:seconds) + options[:lock][:for]) || (time + 5 + :rand.uniform(15))
      lock_type = options[:lock][:type] || :spawn
      {{lock_server, lock_process}, lock_type, lock_until}
    else
      nil
    end
  end

  def obtain_lock!(mod, ref, context, options \\ %{lock: %{}}) do
    if mod.schema_online?() do
      lock = {{lock_server, lock_process}, _lock_type, _lock_until} = mod.prepare_lock(options, true)
      entity = mod.get!(ref, context, options)
      time = options[:time] || :os.system_time()
      if entity do
        case entity.lock do
          nil -> {:ack, put_in(entity, [Access.key(:lock)], lock) |> mod.update!(context, options)}
          {{s,p}, _lt, lu} ->
            cond do
              options[:force] -> {:ack, put_in(entity, [Access.key(:lock)], lock) |> mod.update!(context, options)}
              time > lu -> {:ack, put_in(entity, [Access.key(:lock)], lock) |> mod.update!(context, options)}
              s == lock_server and p == lock_process -> {:ack, put_in(entity, [Access.key(:lock)], lock) |> mod.update!(context, options)}
              options[:conditional_checkout] ->
                check = case options[:conditional_checkout] do
                  v when is_function(v) -> v.(entity)
                  {m,f,1} -> apply(m, f, [entity])
                  _ -> false
                end
                if check do
                  {:ack, put_in(entity, [Access.key(:lock)], lock) |> mod.update!(context, options)}
                else
                  {:nack, {:locked, entity}}
                end
              true -> {:nack, {:locked, entity}}
            end
          _o -> {:nack, {:invalid, entity}}
        end
      else
        e = mod.new(ref, context, options)
            |> put_in([Access.key(:lock)], lock)
            |> mod.create!(context, options)
        {:ack, e}
      end
    else
      {:nack, {:error, :schema_offline}}
    end
  end

  def release_lock!(mod, ref, context, options \\ %{}) do
    if mod.schema_online?() do
      time = options[:time] || :os.system_time()
      entity = mod.get!(ref, context, options)
      if entity do
        case entity.lock do
          nil -> {:ack, entity}
          {{s,p}, lt, lu} ->
            _lock = {{lock_server, lock_process}, lock_type, _lock_until} = mod.prepare_lock(options, true)
            cond do
              options[:force] ->
                {:ack, put_in(entity, [Access.key(:lock)], nil) |> mod.update!(context, options)}
              time > lu ->
                {:ack, put_in(entity, [Access.key(:lock)], nil) |> mod.update!(context, options)}
              s == lock_server and p == lock_process and lt == lock_type -> {:ack, put_in(entity, [Access.key(:lock)], nil) |> mod.update!(context, options)}
              true -> {:nack, {:not_owned, entity}}
            end
        end
      else
        {:ack, nil}
      end
    else
      {:nack, {:error, :schema_offline}}
    end
  end
end # end module
