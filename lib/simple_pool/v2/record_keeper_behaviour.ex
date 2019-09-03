#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.RecordKeeperBehaviour do

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.ServerBehaviour.Default)
    option_settings = implementation.prepare_options(options)

    quote do
      use Agent

      @pool :pending
      @pool_worker_state_entity :pending
      use Noizu.SimplePool.V2.SettingsBehaviour.Inherited, unquote([option_settings: option_settings])

      def initial_value(worker, args, context) do
        %{}
      end

      def start_link(worker, args, context) do
        Agent.start_link(fn -> initial_value(worker, args, context) end, name: agent(worker))
      end

      def agent(worker) do
        ref = @pool_worker_state_entity.ref(worker)
        {__MODULE__, ref}
      end

      def increment(worker, record) do

        Agent.get_and_update(agent(worker),
          fn(state) ->
            state = update_in(state, [record], &( (&1 || 0) + 1))
            {state[record], state}
          end
        )
      end

      def decrement(worker, record) do
        Agent.get_and_update(agent(worker),
          fn(state) ->
            state = update_in(state, [record], &( (&1 || 0) - 1))
            {state[record], state}
          end
        )
      end

      def get(worker, record) do
        Agent.get(agent(worker),
          fn(state) ->
            state[record]
          end
        )
      end

      def set(worker, record, value) do
        Agent.update(agent(worker),
          fn(state) ->
            put_in(state, [record], value)
          end
        )
      end

      def get_state(worker) do
        Agent.get(agent(worker),
          fn(state) ->
            state
          end
        )
      end

      def set_state(worker, records) do
        Agent.update(agent(worker),
          fn(state) ->
            records
          end
        )
      end

      #===============================================================================================================
      # Overridable
      #===============================================================================================================
      defoverridable [
        initial_value: 3,
        start_link: 3,
        increment: 2,
        decrement: 2,
        get: 2,
        set: 3,
        get_state: 1,
        set_state: 2,
      ]
    end
  end

end
