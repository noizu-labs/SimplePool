#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Support.TestWorkerEntity do
  @vsn 1.0

  #-----------------------------------------------------------------------------
  # aliases, imports, uses,
  #-----------------------------------------------------------------------------
  alias Noizu.ElixirCore.CallingContext
  require Logger

  #-----------------------------------------------------------------------------
  # Struct & Types
  #-----------------------------------------------------------------------------
  @type t :: %__MODULE__{
               identifier: Types.entity_reference,
               data: Map.t,
               vsn: Types.vsn
             }

  defstruct [
    identifier: nil,
    data: %{},
    vsn: @vsn
  ]

  use Noizu.SimplePool.InnerStateBehaviour,
      pool: Noizu.SimplePool.Support.TestPool,
      override: [:load]

  #-----------------------------------------------------------------------------
  # Behaviour
  #-----------------------------------------------------------------------------
  def load(ref), do: load(ref, nil, nil)
  def load(ref, context), do: load(ref, nil, context)
  def load(ref, _options, _context) do
    %__MODULE__{
      identifier: id(ref)
    }
  end

  #-----------------------------------------------------------------------------
  # Implementation
  #-----------------------------------------------------------------------------
  def test_s_call!(this, value, context) do
    state = put_in(this, [Access.key(:data), :s_call!], value)
    {:reply, :s_call!, state}
  end
  def test_s_call(this, value, context), do: {:reply, :s_call, put_in(this, [Access.key(:data), :s_call], value)}
  def test_s_cast!(this, value, context), do: {:noreply,  put_in(this, [Access.key(:data), :s_cast!], value)}
  def test_s_cast(this, value, context), do: {:noreply,  put_in(this, [Access.key(:data), :s_cast], value)}

  #-----------------------------------------------------------------------------
  # call_forwarding
  #-----------------------------------------------------------------------------
  def call_forwarding({:test_s_call!, value}, context, _from, %__MODULE__{} = this), do: test_s_call!(this, value, context)
  def call_forwarding({:test_s_call, value}, context, _from, %__MODULE__{} = this), do: test_s_call(this, value, context)


  def call_forwarding({:test_s_cast!, value}, context, %__MODULE__{} = this), do: test_s_cast!(this, value, context)
  def call_forwarding({:test_s_cast, value}, context, %__MODULE__{} = this), do: test_s_cast(this, value, context)

  #-------------------
  # id/1
  #-------------------
  def id({:ref, __MODULE__, identifier}), do: identifier
  def id("ref.noizu-test." <> identifier), do: identifier
  def id(%__MODULE__{} = entity), do: entity.identifier

  #-------------------
  # ref/1
  #-------------------
  def ref({:ref, __MODULE__, identifier}), do: {:ref, __MODULE__, identifier}
  def ref("ref.noizu-test." <> identifier), do: {:ref, __MODULE__, identifier}
  def ref(%__MODULE__{} = entity), do: {:ref, __MODULE__, entity.identifier}

  #-------------------
  # sref/1
  #-------------------
  def sref({:ref, __MODULE__, identifier}), do: "ref.noizu-test.#{identifier}"
  def sref("ref.noizu-test." <> identifier), do: "ref.noizu-test.#{identifier}"
  def sref(%__MODULE__{} = entity), do: "ref.noizu-test.#{entity.identifier}"

  #-------------------
  # entity/2
  #-------------------
  def entity(ref, options \\ %{})
  def entity({:ref, __MODULE__, identifier}, _options), do: %__MODULE__{identifier: identifier}
  def entity("ref.noizu-test." <> identifier, _options), do: %__MODULE__{identifier: identifier}
  def entity(%__MODULE__{} = entity, _options), do: entity

  #-------------------
  # entity!/2
  #-------------------
  def entity!(ref, options \\ %{})
  def entity!({:ref, __MODULE__, identifier}, _options), do: %__MODULE__{identifier: identifier}
  def entity!("ref.noizu-test." <> identifier, _options), do: %__MODULE__{identifier: identifier}
  def entity!(%__MODULE__{} = entity, _options), do: entity


  #-------------------
  # record/2
  #-------------------
  def record(ref, options \\ %{})
  def record({:ref, __MODULE__, identifier}, _options), do: %__MODULE__{identifier: identifier}
  def record("ref.noizu-test." <> identifier, _options), do: %__MODULE__{identifier: identifier}
  def record(%__MODULE__{} = entity, _options), do: entity

  #-------------------
  # record!/2
  #-------------------
  def record!(ref, options \\ %{})
  def record!({:ref, __MODULE__, identifier}, _options), do: %__MODULE__{identifier: identifier}
  def record!("ref.noizu-test." <> identifier, _options), do: %__MODULE__{identifier: identifier}
  def record!(%__MODULE__{} = entity, _options), do: entity



  defimpl Noizu.ERP, for: Noizu.SimplePool.Support.TestWorkerEntity do
    def id(obj) do
      obj.identifier
    end # end sref/1

    def ref(obj) do
      {:ref, Noizu.SimplePool.Support.TestWorkerEntity, obj.identifier}
    end # end ref/1

    def sref(obj) do
      "ref.noizu-test.#{obj.identifier}"
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

end # end defmacro
