#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.Dispatch.MonitorRepo do
  def new(ref, event, details, _context, options \\ %{}) do
    time = options[:time] || :os.system_time(:seconds)
    %Noizu.SimplePool.Database.Dispatch.MonitorTable{identifier: ref, time: time, event: event, details: details}
  end

  #-------------------------
  #
  #-------------------------
  def get!(id, _context, _options \\ %{}) do
    id |> Noizu.SimplePool.Database.Dispatch.MonitorTable.read!()
  end

  def update!(entity, _context, _options \\ %{}) do
    entity
    |> Noizu.SimplePool.Database.Dispatch.MonitorTable.write!()
  end

  def create!(entity, _context, _options \\ %{}) do
    entity
    |> Noizu.SimplePool.Database.Dispatch.MonitorTable.write!()
  end

  def delete!(entity, _context, _options \\ %{}) do
    Noizu.SimplePool.Database.Dispatch.MonitorTable.delete!(entity)
    entity
  end

  #-------------------------
  #
  #-------------------------
  def get(id, _context, _options \\ %{}) do
    id |> Noizu.SimplePool.Database.Dispatch.MonitorTable.read()
  end

  def update(entity, _context, _options \\ %{}) do
    entity
    |> Noizu.SimplePool.Database.Dispatch.MonitorTable.write()
  end

  def create(entity, _context, _options \\ %{}) do
    entity
    |> Noizu.SimplePool.Database.Dispatch.MonitorTable.write()
  end

  def delete(entity, _context, _options \\ %{}) do
    Noizu.SimplePool.Database.Dispatch.MonitorTable.delete(entity)
    entity
  end
end