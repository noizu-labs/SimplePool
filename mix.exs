defmodule Noizu.SimplePool.Mixfile do
  use Mix.Project

  def project do
    [app: :noizu_simple_pool,
     version: "0.0.8",
     elixir: "~> 1.3",
     package: package(),
     deps: deps(),
     description: "Noizu Simple Pool"
   ]
  end

  defp package do
    [
      maintainers: ["noizu"],
      licenses: ["Apache License 2.0"],
      links: %{"GitHub" => "https://github.com/noizu/SimplePool"}
    ]
  end

  def application do
    [ applications: [:logger] ]
  end

  defp deps do
    [ { :ex_doc, "~> 0.11", only: [:dev] } ]
  end

end
