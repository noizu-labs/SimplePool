#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :ex_doc, :markdown_processor, ExDoc.Markdown.Hoedown


config :noizu_mnesia_versioning,
       topology_provider: Noizu.SimplePool.Support.TopologyProvider,
       schema_provider: Noizu.SimplePool.Support.SchemaProvider,
       mnesia_migrate_on_start: false


config :logger, :console,
       format: "$time $metadata[$level] $message\n",
       metadata: [:context_token]
