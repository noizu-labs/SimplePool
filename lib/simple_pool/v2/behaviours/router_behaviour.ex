#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.RouterBehaviour do
  require Logger


  defmacro __using__(_options) do
    quote do
      def router_by_name_test do
        :test
      end
    end
  end

end