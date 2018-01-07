#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.DispatchRepo do
  use Noizu.SimplePool.DispatchRepoBehaviour,
    dispatch_table: Noizu.SimplePool.Database.DispatchTable
end