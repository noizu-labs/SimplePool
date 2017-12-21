#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Support.SchemaProvider do
  use Amnesia
  @behaviour Noizu.MnesiaVersioning.SchemaBehaviour

  def neighbors() do
    [node()]
  end

  #-----------------------------------------------------------------------------
  # ChangeSets
  #-----------------------------------------------------------------------------
  def change_sets do
    Noizu.SimplePool.Support.Schema.Core.change_sets()
  end

end # End Mix.Task.Migrate
