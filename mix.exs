#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Mixfile do
  use Mix.Project

  def project do
    [app: :noizu_simple_pool,
     version: "2.2.6",
     elixir: "~> 1.13",
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
    [
      applications: [:logger],
      extra_applications: [:amnesia, :noizu_mnesia_versioning, :noizu_scaffolding, :noizu_core, :fastglobal, :semaphore]

    ]
  end # end application

  defp deps do
    [
      {:ex_doc, "~> 0.28.3", only: [:dev, :test], optional: true}, # Documentation Provider
      {:markdown, github: "devinus/markdown", only: [:dev], optional: true}, # Markdown processor for ex_doc
      {:amnesia, git: "https://github.com/noizu/amnesia.git", ref: "9266002"}, # Mnesia Wrapper
      {:noizu_scaffolding, github: "noizu/ElixirScaffolding", tag: "1.2.6"},
      {:fastglobal, "~> 1.0"}, # https://github.com/discordapp/fastglobal
      {:semaphore, "~> 1.0"}, # https://github.com/discordapp/semaphore
      {:redix, github: "whatyouhide/redix", tag: "v0.7.0", optional: true},
      {:poison, "~> 3.1.0", optional: true},
      {:elixir_uuid, "~> 1.2", only: :test, optional: true},
      {:plug, "~> 1.11.1", optional: true},
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
