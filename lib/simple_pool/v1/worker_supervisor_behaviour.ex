#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.WorkerSupervisorBehaviour do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList
  require Logger
  @callback start_link() :: any
  @callback init(any) :: any

  @methods ([:start_link, :child, :init, :verbose, :options, :option_settings])

  @default_max_seconds (5)
  @default_max_restarts (1000)
  @default_strategy (:one_for_one)

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: :auto},
        restart_type: %OptionValue{option: :restart_type, default: Application.get_env(:noizu_simple_pool, :pool_restart_type, :transient)},
        max_restarts: %OptionValue{option: :max_restarts, default: Application.get_env(:noizu_simple_pool, :pool_max_restarts, @default_max_restarts)},
        max_seconds: %OptionValue{option: :max_seconds, default: Application.get_env(:noizu_simple_pool, :pool_max_seconds, @default_max_seconds)},
        strategy: %OptionValue{option: :strategy, default: Application.get_env(:noizu_simple_pool, :pool_strategy, @default_strategy)}
      }
    }

    initial = OptionSettings.expand(settings, options)
    modifications = Map.put(initial.effective_options, :required, List.foldl(@methods, %{}, fn(x, acc) -> Map.put(acc, x, initial.effective_options.only[x] && !initial.effective_options.override[x]) end))
    %OptionSettings{initial| effective_options: Map.merge(initial.effective_options, modifications)}
  end


  def default_verbose(verbose, base) do
    if verbose == :auto do
      if Application.get_env(:noizu_simple_pool, base, %{})[:PoolSupervisor][:verbose] do
        Application.get_env(:noizu_simple_pool, base, %{})[:PoolSupervisor][:verbose]
      else
        Application.get_env(:noizu_simple_pool, :verbose, false)
      end
    else
      verbose
    end
  end

  defmacro __using__(options) do
    option_settings = prepare_options(options)
    options = option_settings.effective_options

    required = options.required
    max_restarts = options.max_restarts
    max_seconds = options.max_seconds
    strategy = options.strategy
    restart_type = options.restart_type
    verbose = options.verbose

    quote do
      #@behaviour Noizu.SimplePool.WorkerSupervisorBehaviour
      #@before_compile unquote(__MODULE__)
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
      @worker Module.concat([@base, "Worker"])
      use DynamicSupervisor
      import unquote(__MODULE__)
      require Logger

      @strategy unquote(strategy)
      @restart_type unquote(restart_type)
      @max_restarts unquote(max_restarts)
      @max_seconds unquote(max_seconds)

      @base_verbose (unquote(verbose))
      @option_settings unquote(Macro.escape(option_settings))
      @options unquote(Macro.escape(options))

      if (unquote(required.verbose)) do
        def verbose(), do: default_verbose(@base_verbose, @base)
      end

      if (unquote(required.option_settings)) do
        def option_settings(), do: @option_settings
      end

      if (unquote(required.options)) do
        def options(), do: @options
      end
      
      # @start_link
      if (unquote(required.start_link)) do
        def start_link(definition, context) do
          if verbose() do
            Logger.info(fn -> {@base.banner("#{__MODULE__}.start_link"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
            :skip
          end
          DynamicSupervisor.start_link(__MODULE__, [definition, context], [{:name, __MODULE__}])
        end
      end # end start_link


      # @init
      if (unquote(required.init)) do
        def init([definition, context]) do
          if verbose() do
            Logger.info(fn -> {Noizu.SimplePool.Behaviour.banner("#{__MODULE__} INIT", "args: #{inspect context}"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
          end
          DynamicSupervisor.init([{:strategy,  @strategy}, {:max_restarts, @max_restarts}, {:max_seconds, @max_seconds}])
        end
      end # end init

      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
  
      def handle_call(:force_kill, _from, _state) do
        # For testing worker_supervisor recovery.
        throw "Crash WorkerSupervisor"
      end
      
      def handle_call(uncaught, _from, state) do
        Logger.info(fn -> "Uncaught handle_call to #{__MODULE__} . . . #{inspect uncaught}"  end)
        {:noreply, state}
      end

      def handle_cast(uncaught, state) do
        Logger.info(fn -> "Uncaught handle_cast to #{__MODULE__} . . . #{inspect uncaught}"  end)
        {:noreply, state}
      end

      def handle_info(uncaught, state) do
        Logger.info(fn -> "Uncaught handle_info to #{__MODULE__} . . . #{inspect uncaught}"  end)
        {:noreply, state}
      end
    end # end quote
  end # end __before_compile__

end
