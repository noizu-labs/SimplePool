#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.DispatchRepoBehaviour do
  use Amnesia


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
        Noizu.SimplePool.DispatchRepoBehaviourDefault.prepare_lock(options, force)
      end

      def new(ref, context, options \\ %{}) do
        Noizu.SimplePool.DispatchRepoBehaviourDefault.new(__MODULE__, ref, context, options)
      end

      def obtain_lock!(ref, context, options \\ %{lock: %{}}) do
        Noizu.SimplePool.DispatchRepoBehaviourDefault.obtain_lock!(__MODULE__, ref, context, options)
      end

      def release_lock!(ref, context, options \\ %{}) do
        Noizu.SimplePool.DispatchRepoBehaviourDefault.release_lock!(__MODULE__, ref, context, options)
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


        def id_ok(o) do
          r = id(o)
          r && {:ok, r} || {:error, o}
        end
        def ref_ok(o) do
          r = ref(o)
          r && {:ok, r} || {:error, o}
        end
        def sref_ok(o) do
          r = sref(o)
          r && {:ok, r} || {:error, o}
        end
        def entity_ok(o, options \\ %{}) do
          r = entity(o, options)
          r && {:ok, r} || {:error, o}
        end
        def entity_ok!(o, options \\ %{}) do
          r = entity!(o, options)
          r && {:ok, r} || {:error, o}
        end

      end # end defimpl
    end # end quote
  end # end __suing__
end # end module
