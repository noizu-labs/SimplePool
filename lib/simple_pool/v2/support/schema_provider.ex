#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Support.SchemaProvider do
  use Amnesia
  @behaviour Noizu.MnesiaVersioning.SchemaBehaviour

  def neighbors() do
    [node()]
  end

  #-----------------------------------------------------------------------------
  # ChangeSets
  #-----------------------------------------------------------------------------
  def change_sets do
    Noizu.SimplePool.V2.Support.Schema.Core.change_sets()
  end

end # End Mix.Task.Migrate
