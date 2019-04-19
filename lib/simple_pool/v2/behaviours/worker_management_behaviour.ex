#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerManagementBehaviour do
  require Logger


  defmacro __using__(_options) do
    quote do
      @parent Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat()

      @router Module.concat(@parent, Router)


      def cross_test do
        {:ok, @router.router_by_name_test(), @parent.pool()}
      end

    end
  end

end