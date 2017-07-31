defmodule Noizu.SimplePool.Mixfile do
  use Mix.Project

  def project do
    [app: :noizu_simple_pool,
     version: "1.1.1",
     elixir: "~> 1.4",
     package: package(),
     deps: deps(),
     description: "Noizu Simple Pool",
     docs: docs()
   ]
 end # end project

  defp package do
    [
      maintainers: ["noizu"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/noizu/SimplePool"}
    ]
  end # end package

  def application do
    [ applications: [:logger] ]
  end # end application

  defp deps do
    [
      {:ex_doc, "~> 0.16.2", only: [:dev], optional: true}, # Documentation Provider
      {:markdown, github: "devinus/markdown", only: [:dev], optional: true}, # Markdown processor for ex_doc
    ]
  end # end deps

  defp docs do
    [
      source_url_pattern: "https://github.com/noizu/SimplePool/blob/master/%{path}#L%{line}",
      extras: ["README.md"]
    ]
  end # end docs
end
