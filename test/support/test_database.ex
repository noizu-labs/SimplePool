#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

use Amnesia

defdatabase Noizu.SimplePool.TestDatabase do

  #--------------------------------------
  # Dispatch
  #--------------------------------------
  deftable TestV2Pool.DispatchTable, [:identifier, :server, :entity], type: :set, index: [] do
    @type t :: %TestV2Pool.DispatchTable{identifier: tuple, server: atom, entity: Noizu.SimplePool.V2.DispatchEntity.t}
  end

  deftable TestV2TwoPool.DispatchTable, [:identifier, :server, :entity], type: :set, index: [] do
    @type t :: %TestV2TwoPool.DispatchTable{identifier: tuple, server: atom, entity: Noizu.SimplePool.V2.DispatchEntity.t}
  end

  deftable TestV2ThreePool.DispatchTable, [:identifier, :server, :entity], type: :set, index: [] do
    @type t :: %TestV2ThreePool.DispatchTable{identifier: tuple, server: atom, entity: Noizu.SimplePool.V2.DispatchEntity.t}
  end

end