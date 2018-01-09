#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.DispatchRepoBehaviour do
  use Amnesia

  def default_new(mod, ref, _context, options \\ %{}) do
    state = options[:state] || :new
    server = options[:server] || :pending
    lock = mod.prepare_lock(options)
    %Noizu.SimplePool.DispatchEntity{identifier: ref, server: server, state: state, lock: lock}
  end

  def default_prepare_lock(options, force \\ false) do
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

  def default_obtain_lock!(mod, ref, context, options \\ %{lock: %{}}) do
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

  def default_release_lock!(mod, ref, context, options \\ %{}) do
    if mod.schema_online?() do
      time = options[:time] || :os.system_time()
      _lock = {{lock_server, lock_process}, lock_type, _lock_until} = mod.prepare_lock(options, true)
      entity = mod.get!(ref, context, options)
      if entity do
        case entity.lock do
          nil -> {:ack, entity}
          {{s,p}, lt, lu} ->
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

  defmacro __using__(options) do
    dispatch_table = options[:dispatch_table]

    quote do
      @dispatch_table unquote(dispatch_table)
      use Amnesia
      import unquote(__MODULE__)

      def schema_online?() do
        case Amnesia.Table.wait([@dispatch_table], 5) do
          :ok -> true
          _ -> false
        end
      end

      def prepare_lock(options, force \\ false) do
        default_prepare_lock(options, force)
      end

      def new(ref, context, options \\ %{}) do
        default_new(__MODULE__, ref, context, options)
      end

      def obtain_lock!(ref, context, options \\ %{lock: %{}}) do
        default_obtain_lock!(__MODULE__, ref, context, options)
      end

      def release_lock!(ref, context, options \\ %{}) do
        default_release_lock!(__MODULE__, ref, context, options)
      end

      def workers!(host, service_entity, _context, options \\ %{}) do
        if schema_online?() do
          v = @dispatch_table.match!([identifier: {:ref, service_entity, :_}, server: host])
              |> Amnesia.Selection.values
          {:ack, v}
        else
          {:nack, []}
        end
      end

      #-------------------------
      #
      #-------------------------
      def get!(id, _context, _options \\ %{}) do
        if schema_online?() do
          id
          |> @dispatch_table.read!()
          |> Noizu.ERP.entity()
        else
          nil
        end
      end

      def update!(%Noizu.SimplePool.DispatchEntity{} = entity, _context, options \\ %{}) do
        if schema_online?() do
          %@dispatch_table{identifier: entity.identifier, server: entity.server, entity: entity}
          |> @dispatch_table.write!()
          |> Noizu.ERP.entity()
        else
          nil
        end

      end

      def create!(%Noizu.SimplePool.DispatchEntity{} = entity, _context, options \\ %{}) do
        if schema_online?() do
          %@dispatch_table{identifier: entity.identifier, server: entity.server, entity: entity}
          |> @dispatch_table.write!()
          |> Noizu.ERP.entity()
        else
          nil
        end
      end

      def delete!(entity, _context, _options \\ %{}) do
        if schema_online?() do
          @dispatch_table.delete!(entity.identifier)
        end
        entity
      end

      #-------------------------
      #
      #-------------------------
      def get(id, _context, _options \\ %{}) do
        if schema_online?() do
          id
          |> @dispatch_table.read()
          |> Noizu.ERP.entity()
        else
          nil
        end
      end

      def update(%Noizu.SimplePool.DispatchEntity{} = entity, _context, options \\ %{}) do
        if schema_online?() do
          %@dispatch_table{identifier: entity.identifier, server: entity.server, entity: entity}
          |> @dispatch_table.write()
          |> Noizu.ERP.entity()
        else
          nil
        end
      end

      def create(%Noizu.SimplePool.DispatchEntity{} = entity, _context, options \\ %{}) do
        if schema_online?() do
          %@dispatch_table{identifier: entity.identifier, server: entity.server, entity: entity}
          |> @dispatch_table.write()
          |> Noizu.ERP.entity()
        else
          nil
        end
      end

      def delete(entity, _context, _options \\ %{}) do
        if schema_online?() do
          @dispatch_table.delete(entity.identifier)
          entity
        else
          nil
        end
      end

      defimpl Noizu.ERP, for: @dispatch_table do
        def id(obj) do
          obj.identifier
        end # end sref/1

        def ref(obj) do
          {:ref, Noizu.SimplePool.DispatchEntity, obj.identifier}
        end # end ref/1

        def sref(obj) do
          "ref.noizu-dispatch.[#{Noizu.ERP.sref(obj.identifier)}]"
        end # end sref/1

        def record(obj, _options \\ nil) do
          obj
        end # end record/2

        def record!(obj, _options \\ nil) do
          obj
        end # end record/2

        def entity(obj, _options \\ nil) do
          obj.entity
        end # end entity/2

        def entity!(obj, _options \\ nil) do
          obj.entity
        end # end defimpl EntityReferenceProtocol, for: Tuple
      end # end defimpl
    end # end quote
  end # end __suing__
end # end module