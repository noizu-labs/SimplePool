#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Server.Router.DefaultImplementation do



  def extended_call(module, ref, timeout, call, context) do
    # @TODO @PRI-0
    # if redirect router then: {:s_call!, {__MODULE__, ref, timeout}, {:s, call, context}}
    # else: {:s, call, context}
    {:s_call!, {module, ref, timeout}, {:s, call, context}}
  end


end