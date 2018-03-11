#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Mixfile do
  use Mix.Project

  def project do
    [app: :noizu_simple_pool,
     version: "1.3.23",
     elixir: "~> 1.4",
     package: package(),
     deps: deps(),
     description: "Noizu Simple Pool",
     docs: docs(),
     elixirc_paths: elixirc_paths(Mix.env),
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
      {:ex_doc, "~> 0.16.2", only: [:dev, :test], optional: true}, # Documentation Provider
      {:markdown, github: "devinus/markdown", only: [:dev], optional: true}, # Markdown processor for ex_doc
      {:amnesia, git: "https://github.com/meh/amnesia.git", ref: "87d8b4f", optional: true}, # Mnesia Wrapper
      {:noizu_mnesia_versioning, github: "noizu/MnesiaVersioning", tag: "0.1.8"},
      {:noizu_core, github: "noizu/ElixirCore", tag: "1.0.2"},
    ]
  end # end deps

  defp docs do
    [
      source_url_pattern: "https://github.com/noizu/SimplePool/blob/master/%{path}#L%{line}",
      extras: ["README.md"]
    ]
  end # end docs

  defp elixirc_paths(:test), do: ["lib","test/support"]
  defp elixirc_paths(_), do: ["lib"]

end
