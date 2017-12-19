#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.DispatchEntity do
  @type t :: %__MODULE__{
               identifier: any,
               state: atom,
               server: atom,
               lock: nil | {{atom, pid}, atom, integer}
             }

  defstruct [
    identifier: nil,
    state: :spawning,
    server: nil,
    lock: nil
  ]

  def id(%__MODULE__{} = e), do: e.identifier
  def id({:ref, __MODULE__, identifier}), do: identifier

  def ref(%__MODULE__{} = e), do: {:ref, __MODULE__, e.identifier}
  def ref({:ref, __MODULE__, identifier}), do: {:ref, __MODULE__, identifier}

  def sref(%__MODULE__{} = e), do: "ref.noizu-dispatch.[#{Noizu.ERP.sref(e.identifier)}]"
  def sref({:ref, __MODULE__, identifier}), do: "ref.noizu-dispatch.#{identifier}"

  def entity(ref, options \\ %{})
  def entity({:ref, __MODULE__, identifier}, _options), do: Noizu.SimplePool.DispatchRepo.get(identifier)
  def entity(%__MODULE__{} = e, _options), do: e

  def entity!(ref, options \\ %{})
  def entity!({:ref, __MODULE__, identifier}, _options), do: Noizu.SimplePool.DispatchRepo.get!(identifier)
  def entity!(%__MODULE__{} = e, _options), do: e

  def record(ref, options \\ %{})
  def record({:ref, __MODULE__, identifier}, _options) do
    entity = Noizu.SimplePool.DispatchRepo.get(identifier)
    entity && %Noizu.SimplePool.Database.DispatchTable{identifier: entity.identifier, server: entity.server, entity: entity}
  end
  def record(%__MODULE__{} = entity, _options) do
    %Noizu.SimplePool.Database.DispatchTable{identifier: entity.identifier, server: entity.server, entity: entity}
  end

  def record!(ref, options \\ %{})
  def record!({:ref, __MODULE__, identifier}, _options) do
    entity = Noizu.SimplePool.DispatchRepo.get!(identifier)
    entity && %Noizu.SimplePool.Database.DispatchTable{identifier: entity.identifier, server: entity.server, entity: entity}
  end
  def record!(%__MODULE__{} = entity, _options) do
    %Noizu.SimplePool.Database.DispatchTable{identifier: entity.identifier, server: entity.server, entity: entity}
  end

  def has_permission(ref, permission, context), do: true
  def has_permission!(ref, permission, context), do: true

  defimpl Noizu.ERP, for: Noizu.SimplePool.DispatchEntity do
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
      obj
    end # end entity/2

    def entity!(obj, _options \\ nil) do
      obj
    end # end defimpl EntityReferenceProtocol, for: Tuple
  end


  defimpl Noizu.ERP, for: Noizu.SimplePool.Database.DispatchTable do
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
  end



end