defmodule Noizu.SmartPool.Mixfile do
  use Mix.Project

  def project do
    [app: :noizu_smart_pool,
     version: "0.0.1",
     elixir: "~> 1.3",
     package: package(),
     deps: deps(),
     description: "Noizu Smart Pool"
   ]
  end

  defp package do
    [
      maintainers: ["noizu"],
      licenses: ["Apache License 2.0"],
      links: %{"GitHub" => "https://github.com/noizu/SmartPool"}
    ]
  end

  def application do
    [ applications: [:logger] ]
  end

  defp deps do
    [ { :ex_doc, "~> 0.11", only: [:dev] } ]
  end

end
