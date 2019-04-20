#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerSupervisorBehaviour do
  @moduledoc """
    WorkerSupervisorBehaviour provides the logic for managing a pool of workers. The top level Pool Supervisors will generally
    contain a number of WorkerSupervisors that in turn are referenced by Pool.Server to access, kill and spawn worker processes.

    @todo increase level of OTP nesting and hide some of the communication complexity from Pool.Server
  """

  require Logger
  @callback start_link(any, any) :: any

  @callback child(any, any) :: any
  @callback child(any, any, any) :: any
  @callback child(any, any, any, any) :: any

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.WorkerSupervisor.DefaultImplementation)
    option_settings = implementation.prepare_options(options)
    options = option_settings.effective_options

    max_restarts = options.max_restarts
    max_seconds = options.max_seconds
    strategy = options.strategy
    restart_type = options.restart_type

    # Temporary Hard Code
    max_supervisors = 100
    worker_supervisor_provider = Noizu.SimplePool.V2.WorkerSupervisor.Layer2Behaviour

    quote do
      @behaviour Noizu.SimplePool.V2.WorkerSupervisorBehaviour
      use Supervisor
      require Logger

      @implementation unquote(implementation)
      @parent unquote(__MODULE__)
      @module __MODULE__
      @module_name "#{@module}"

      # Related Modules.
      @pool @implementation.pool(@module)
      @meta_key Module.concat(@module, "Meta")

      @options :override
      @option_settings :override

      @strategy unquote(strategy)
      @restart_type unquote(restart_type)
      @max_seconds unquote(max_seconds)
      @max_restarts unquote(max_restarts)

      @max_supervisors unquote(max_supervisors)

      use Noizu.SimplePool.V2.PoolSettingsBehaviour.Inherited, unquote([option_settings: option_settings])

      @doc """
      OTP start_link entry point.
      """
      def start_link(definition, context) do
        if verbose() do
          Logger.info(fn -> {banner("#{__MODULE__}.start_link"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
          :skip
        end
        Supervisor.start_link(__MODULE__, [definition, context], [{:name, __MODULE__}])
      end

      @doc """
      OTP init entry point.
      """
      def init([definition, context] =args) do
        verbose() && Logger.info(fn -> {banner("#{__MODULE__} INIT", "args: #{inspect context}"), Noizu.ElixirCore.CallingContext.metadata(context) } end)

        # @todo provide different max_restarts, max_seconds for children
        available_supervisors()
        |> Enum.map(&(supervisor(&1, [definition, context], [restart: :permanent, max_restarts: @max_restarts, max_seconds: @max_seconds] )))
        |> supervise([{:strategy,  @strategy}, {:max_restarts, @max_restarts}, {:max_seconds, @max_seconds}])
      end

      def count_children() do
        throw :pri0
      end

      def group_children(lambda) do
        throw :pri0
      end


      def available_supervisors() do
        # Temporary Hard Code - should come from meta()[:active_supervisors] or similar.
        leading = round(:math.floor(:math.log10(@max_supervisors))) + 1
        Enum.map(0 .. @max_supervisors, fn(i) ->
          Module.concat(__MODULE__, "Seg_#{String.pad_leading("#{i}", leading, "0")}")
        end)
      end

      module = __MODULE__
      leading = round(:math.floor(:math.log10(@max_supervisors))) + 1
      for i <- 0 .. @max_supervisors do
        defmodule :"#{module}.Seg_#{String.pad_leading("#{i}", leading, "0")}" do
          use unquote(worker_supervisor_provider), unquote(options[:layer2_options] || [])
        end
      end

      defoverridable [
        start_link: 2,
        init: 1,
        available_supervisors: 0,
        group_children: 1,
        count_children: 0,
      ]
    end # end quote
  end #end __using__
end
