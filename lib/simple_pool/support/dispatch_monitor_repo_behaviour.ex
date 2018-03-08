#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.DispatchMonitorRepoBehaviour do

  defmacro __using__(options) do
    monitor_table = options[:monitor_table]

    quote do
      @monitor_table unquote(monitor_table)

      def schema_online?() do
        case Amnesia.Table.wait([@monitor_table], 5) do
          :ok -> true
          _ -> false
        end
      end

      def new(ref, event, details, _context, options \\ %{}) do
        time = options[:time] || :os.system_time(:seconds)
        %@monitor_table{identifier: ref, time: time, event: event, details: details}
      end

      #-------------------------
      #
      #-------------------------
      def get!(id, _context, _options \\ %{}) do
        if schema_online?() do
          id |> @monitor_table.read!()
        else
          nil
        end
      end

      def update!(entity, _context, _options \\ %{}) do
        if schema_online?() do
          entity
          |> @monitor_table.write!()
        else
          nil
        end
      end

      def create!(entity, _context, _options \\ %{}) do
        if schema_online?() do
          entity
          |> @monitor_table.write!()
        else
          nil
        end
      end

      def delete!(entity, _context, _options \\ %{}) do
        if schema_online?() do
          @monitor_table.delete!(entity)
        end
        entity
      end

      #-------------------------
      #
      #-------------------------
      def get(id, _context, _options \\ %{}) do
        if schema_online?() do
          id |> @monitor_table.read()
        else
          nil
        end
      end

      def update(entity, _context, _options \\ %{}) do
        if schema_online?() do
          entity
          |> @monitor_table.write()
        else
          nil
        end
      end

      def create(entity, _context, _options \\ %{}) do
        if schema_online?() do
          entity
          |> @monitor_table.write()
        else
          nil
        end
      end

      def delete(entity, _context, _options \\ %{}) do
        if schema_online?() do
          @monitor_table.delete(entity)
        end
        entity
      end

      defimpl Inspect, for: @monitor_table do
        import Inspect.Algebra
        def inspect(entity, opts) do
          heading = "#WorkerEvent(#{entity.event},#{entity.time})"
          {seperator, end_seperator} = if opts.pretty, do: {"\n   ", "\n"}, else: {" ", " "}
          inner = cond do
            opts.limit == :infinity ->
              concat(["<#{seperator}", to_doc(Map.from_struct(entity), opts), "#{seperator}>"])
            true -> "<>"
          end
          concat [heading, inner]
        end # end inspect/2
      end # end defimpl
    end
  end
end
