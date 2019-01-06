#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.DispatchRepo do
  use Noizu.SimplePool.DispatchRepoBehaviour,
    dispatch_table: Noizu.SimplePool.Database.DispatchTable
end
