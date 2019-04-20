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

  @callback count_children() :: any
  @callback group_children(any) ::any
  @callback available_supervisors() ::any



  @default_max_seconds (5)
  @default_max_restarts (1000)
  @default_strategy (:one_for_one)

  defmodule Default do
    @moduledoc """
    Reusable functionality implemented here to reduce size of generated code.
    """
    alias Noizu.ElixirCore.OptionSettings
    alias Noizu.ElixirCore.OptionValue
    alias Noizu.ElixirCore.OptionList

    def prepare_options(options) do


      default_restart_type = (Application.get_env(:noizu_simple_pool, :worker_pool_restart_type, nil)
                              || Application.get_env(:noizu_simple_pool, :restart_type, :transient))

      default_max_restarts = (Application.get_env(:noizu_simple_pool, :worker_pool_max_restarts, nil)
                              || Application.get_env(:noizu_simple_pool, :max_restarts, @default_max_restarts))

      default_max_seconds = (Application.get_env(:noizu_simple_pool, :worker_pool_max_seconds, nil)
                              || Application.get_env(:noizu_simple_pool, :max_seconds, @default_max_seconds))

      default_strategy = (Application.get_env(:noizu_simple_pool, :worker_pool_strategy, nil)
                             || Application.get_env(:noizu_simple_pool, :pool_strategy, @default_strategy))


      default_layer2_restart_type = (Application.get_env(:noizu_simple_pool, :worker_pool_layer2_restart_type, nil)
                              || Application.get_env(:noizu_simple_pool, :worker_pool_restart_type, nil)
                              || Application.get_env(:noizu_simple_pool, :restart_type, :permanent))

      default_layer2_max_restarts = (Application.get_env(:noizu_simple_pool, :worker_pool_layer2_max_restarts, nil)
                              || Application.get_env(:noizu_simple_pool, :worker_pool_max_restarts, nil)
                              || Application.get_env(:noizu_simple_pool, :max_restarts, @default_max_restarts))

      default_layer2_max_seconds = (Application.get_env(:noizu_simple_pool, :worker_pool_layer2_max_seconds, nil)
                             || Application.get_env(:noizu_simple_pool, :worker_pool_max_seconds, nil)
                             || Application.get_env(:noizu_simple_pool, :max_seconds, @default_max_seconds))

      default_layer2_provider = Noizu.SimplePool.V2.WorkerSupervisor.Layer2Behaviour

      default_max_supervisors = 100

      settings = %OptionSettings{
        option_settings: %{
          verbose: %OptionValue{option: :verbose, default: :auto},
          restart_type: %OptionValue{option: :restart_type, default: default_restart_type},
          max_restarts: %OptionValue{option: :max_restarts, default: default_max_restarts},
          max_seconds: %OptionValue{option: :max_seconds, default: default_max_seconds},
          strategy: %OptionValue{option: :strategy, default: default_strategy},

          max_supervisors: %OptionValue{option: :max_supervisors, default: default_max_supervisors},

          layer2_restart_type: %OptionValue{option: :restart_type, default: default_layer2_restart_type},
          layer2_max_restarts: %OptionValue{option: :max_restarts, default: default_layer2_max_restarts},
          layer2_max_seconds: %OptionValue{option: :max_seconds, default: default_layer2_max_seconds},
          layer2_provider: %OptionValue{option: :layer2_provider, default: default_layer2_provider},
        }
      }
      OptionSettings.expand(settings, options)
    end
  end

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.WorkerSupervisorBehaviour.Default)
    option_settings = implementation.prepare_options(options)
    options = option_settings.effective_options

    # @Todo Temporary Hard Code
    max_supervisors = options.max_supervisors
    layer2_provider = options.layer2_provider

    quote do
      @behaviour Noizu.SimplePool.V2.WorkerSupervisorBehaviour
      use Supervisor
      require Logger

      @implementation unquote(implementation)
      @options :override
      @option_settings :override
      @max_supervisors unquote(max_supervisors)

      use Noizu.SimplePool.V2.PoolSettingsBehaviour.Inherited, unquote([option_settings: option_settings])

      @doc """
      OTP start_link entry point.
      """
      def start_link(definition, context) do
        verbose() && Logger.info(fn -> {banner("#{__MODULE__}.start_link"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
        Supervisor.start_link(__MODULE__, [definition, context], [{:name, __MODULE__}])
      end

      @doc """
      OTP init entry point.
      """
      def init([definition, context] = args) do
        verbose() && Logger.info(fn -> {banner("#{__MODULE__} INIT", "args: #{inspect args}"), Noizu.ElixirCore.CallingContext.metadata(context) } end)

        available_supervisors()
        |> Enum.map(&(supervisor(&1, [definition, context], [restart: @options.layer2_restart_type, max_restarts: @options.layer2_max_restarts, max_seconds: @options.layer2_max_seconds] )))
        |> supervise([{:strategy,  @options.strategy}, {:max_restarts, @options.max_restarts}, {:max_seconds, @options.max_seconds}])
      end




      def available_supervisors() do
        # Temporary Hard Code - should come from meta()[:active_supervisors] or similar.
        leading = round(:math.floor(:math.log10(@max_supervisors))) + 1
        Enum.map(0 .. @max_supervisors, fn(i) ->
          Module.concat(__MODULE__, "Seg#{String.pad_leading("#{i}", leading, "0")}")
        end)
      end
      def group_children(lambda), do: throw :pri0_group_children
      def count_children(), do: throw :pri0_count_children

      defoverridable [
        start_link: 2,
        init: 1,
        available_supervisors: 0,
        group_children: 1,
        count_children: 0,
      ]

      #==================================================
      # Generate Sub Supervisors
      #==================================================
      module = __MODULE__
      leading = round(:math.floor(:math.log10(@max_supervisors))) + 1
      for i <- 0 .. @max_supervisors do
        defmodule :"#{module}.Seg#{String.pad_leading("#{i}", leading, "0")}" do
          use unquote(layer2_provider), unquote(options[:layer2_options] || [])
        end
      end
    end # end quote
  end #end __using__
end
