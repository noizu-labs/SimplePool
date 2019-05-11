#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Mix.Tasks.SecondTestNode do
  use Mix.Task

  def run(_) do
    IO.puts "#{node()} - Semaphore start: #{inspect Semaphore.start(nil, nil)}"
  end

end
