#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Support.TestV2TwoWorkerEntity do
  @vsn 1.0

  #-----------------------------------------------------------------------------
  # aliases, imports, uses,
  #-----------------------------------------------------------------------------
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

  use Noizu.SimplePool.V2.InnerStateBehaviour,
      pool: Noizu.SimplePool.Support.TestV2TwoPool,
      override: [:load, :supervisor_hint]


  def supervisor_hint(ref) do
    id = id(ref)
    cond do
      is_integer(id) -> id
      is_bitstring(id) ->
        "test_" <> ts = id
        String.to_integer(ts)
    end
  end
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
  def test_s_call!(this, value, _context) do
    state = put_in(this, [Access.key(:data), :s_call!], value)
    {:reply, :s_call!, state}
  end
  def test_s_call(this, value, _context), do: {:reply, :s_call, put_in(this, [Access.key(:data), :s_call], value)}
  def test_s_cast!(this, value, _context), do: {:noreply,  put_in(this, [Access.key(:data), :s_cast!], value)}
  def test_s_cast(this, value, _context), do: {:noreply,  put_in(this, [Access.key(:data), :s_cast], value)}


  #-----------------------------------------------------------------------------
  # call_forwarding
  #-----------------------------------------------------------------------------

  #------------------------------------------------------------------------
  # call router
  #------------------------------------------------------------------------
  def call_router_user({:spawn, envelope}, from, state), do: call_router_user(envelope, from, state)
  def call_router_user({:passive, envelope}, from, state), do: call_router_user(envelope, from, state)
  def call_router_user(envelope, _from, state) do
    case envelope do
      {:s, {:test_s_call!, value}, context} -> test_s_call!(state, value, context)
      {:s, {:test_s_call, value}, context} -> test_s_call(state, value, context)
      _ -> nil
    end
  end

  def cast_router_user({:spawn, envelope}, state), do: cast_router_user(envelope, state)
  def cast_router_user({:passive, envelope}, state), do: cast_router_user(envelope, state)
  def cast_router_user(envelope, state) do
    case envelope do
      {:s, {:test_s_cast!, value}, context} -> test_s_cast!(state, value, context)
      {:s, {:test_s_cast, value}, context} -> test_s_cast(state, value, context)
      _ -> nil
    end
  end

  #-------------------
  # id/1
  #-------------------
  def id({:ref, __MODULE__, identifier}), do: identifier
  def id("ref.noizu-test-2." <> identifier), do: identifier
  def id(%__MODULE__{} = entity), do: entity.identifier

  #-------------------
  # ref/1
  #-------------------
  def ref({:ref, __MODULE__, identifier}), do: {:ref, __MODULE__, identifier}
  def ref("ref.noizu-test-2." <> identifier), do: {:ref, __MODULE__, identifier}
  def ref(%__MODULE__{} = entity), do: {:ref, __MODULE__, entity.identifier}

  #-------------------
  # sref/1
  #-------------------
  def sref({:ref, __MODULE__, identifier}), do: "ref.noizu-test-2.#{identifier}"
  def sref("ref.noizu-test-2." <> identifier), do: "ref.noizu-test-2.#{identifier}"
  def sref(%__MODULE__{} = entity), do: "ref.noizu-test-2.#{entity.identifier}"

  #-------------------
  # entity/2
  #-------------------
  def entity(ref, options \\ %{})
  def entity({:ref, __MODULE__, identifier}, _options), do: %__MODULE__{identifier: identifier}
  def entity("ref.noizu-test-2." <> identifier, _options), do: %__MODULE__{identifier: identifier}
  def entity(%__MODULE__{} = entity, _options), do: entity

  #-------------------
  # entity!/2
  #-------------------
  def entity!(ref, options \\ %{})
  def entity!({:ref, __MODULE__, identifier}, _options), do: %__MODULE__{identifier: identifier}
  def entity!("ref.noizu-test-2." <> identifier, _options), do: %__MODULE__{identifier: identifier}
  def entity!(%__MODULE__{} = entity, _options), do: entity


  #-------------------
  # record/2
  #-------------------
  def record(ref, options \\ %{})
  def record({:ref, __MODULE__, identifier}, _options), do: %__MODULE__{identifier: identifier}
  def record("ref.noizu-test-2." <> identifier, _options), do: %__MODULE__{identifier: identifier}
  def record(%__MODULE__{} = entity, _options), do: entity

  #-------------------
  # record!/2
  #-------------------
  def record!(ref, options \\ %{})
  def record!({:ref, __MODULE__, identifier}, _options), do: %__MODULE__{identifier: identifier}
  def record!("ref.noizu-test-2." <> identifier, _options), do: %__MODULE__{identifier: identifier}
  def record!(%__MODULE__{} = entity, _options), do: entity



  def id_ok(o) do
    r = ref(o)
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


  defimpl Noizu.ERP, for: Noizu.SimplePool.Support.TestV2TwoWorkerEntity do
    def id(obj) do
      obj.identifier
    end # end sref/1

    def ref(obj) do
      {:ref, Noizu.SimplePool.Support.TestV2TwoWorkerEntity, obj.identifier}
    end # end ref/1

    def sref(obj) do
      "ref.noizu-test-2.#{obj.identifier}"
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



    def id_ok(o) do
      r = ref(o)
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

  end


  #-----------------------------------------------------------------------------
  # Inspect Protocol
  #-----------------------------------------------------------------------------
  defimpl Inspect, for: Noizu.SimplePool.Support.TestV2TwoWorkerEntity do
    import Inspect.Algebra
    def inspect(entity, opts) do
      heading = "#TestTwoWorkerEntity(#{inspect entity.identifier})"
      {seperator, end_seperator} = if opts.pretty, do: {"\n   ", "\n"}, else: {" ", " "}
      inner = cond do
        opts.limit == :infinity ->
          concat(["<#{seperator}", to_doc(Map.from_struct(entity), opts), "#{end_seperator}>"])
        true -> "<>"
      end
      concat [heading, inner]
    end # end inspect/2
  end # end defimpl

end # end defmacro
