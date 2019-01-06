#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Server.Supervisor.DynamicImplementation do
  use Noizu.SimplePool.V2.Server.Supervisor.Behaviour

  def current_supervisor(module, ref) do
    num_supervisors = module.active_supervisors()
    if num_supervisors == 1 do
      module.supervisor_meta()[:default_supervisor]
    else
      hint = module.supervisor_hint(ref)
      # The logic is designed so that the selected supervisor only changes for a subset of items when adding new supervisors
      # So that, for example, when going from 5 to 6 supervisors only a 6th of entries will be re-assigned to the new bucket.
      index = Enum.reduce(1 .. num_supervisors, 1, fn(x, acc) ->
        n = rem(hint, x) + 1
        (n == x) && n || acc
      end)
      module.supervisor_by_index(index)
    end
  end
end