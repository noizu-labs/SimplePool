defimpl Noizu.ERP, for: Atom do
  def sref(nil), do: nil
  def ref(nil), do: nil
  def id(nil), do: nil
  def entity(nil, _options \\ nil), do: nil
  def entity!(nil, _options \\ nil), do: nil
  def record(nil, _options \\ nil), do: nil
  def record!(nil, _options \\ nil), do: nil
end