#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule  Noizu.SimplePool.Worker.Link do

  @type t :: %__MODULE__{
    ref: any,
    handler: Module,
    handle: pid,
    expire: integer,
    update_after: integer | :infinity,
    state: :dead | :alive | {:error, any} | :invalid | :unknown
  }

  defstruct [
    ref: nil,
    handler: nil,
    handle: nil,
    expire: 0,
    update_after: 300, # Default recheck links after 5 minutes,  increase or reduce depending on how critical delivery of message is. or set to :infinity if other mechanism in place to update.
    state: :unknown
  ]
end
