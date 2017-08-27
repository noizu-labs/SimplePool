#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.Worker.Link do

  @type t :: %__MODULE__{
    ref: any,
    handler: Module,
    handle: pid,
    state: :dead | :alive | {:error, any} | :invalid | :unknown
  }

  defstruct [
    ref: nil,
    handler: nil,
    handle: nil,
    state: :unknown
  ]
end
