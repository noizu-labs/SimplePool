defmodule Noizu.SimplePool.NmidAdapter do
  def generate(a,b) do
    case Application.get_env(:noizu_scaffolding, :default_nmid_generator, nil) do
      nil -> 0x31337
      m -> m.generate(a,b)
    end
  end


  def generate!(a,b) do
    case Application.get_env(:noizu_scaffolding, :default_nmid_generator, nil) do
      nil -> 0x31337
      m -> m.generate!(a,b)
    end
  end
end

