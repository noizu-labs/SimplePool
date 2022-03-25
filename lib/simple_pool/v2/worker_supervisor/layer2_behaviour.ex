#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerSupervisor.Layer2Behaviour do
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

  defmodule Default do
    @moduledoc """
      Provides the default implementation for WorkerSupervisor modules.
      Using the strategy pattern here allows us to move logic out of the WorkerSupervisorBehaviour implementation
      which reduces the amount of generated code, and improve compile times. It additionally allows for developers to provide
      their own alternative implementations.
    """
    alias Noizu.ElixirCore.OptionSettings
    alias Noizu.ElixirCore.OptionValue
    #alias Noizu.ElixirCore.OptionList

    require Logger

    @default_max_seconds (5)
    @default_max_restarts (1000)
    @default_strategy (:one_for_one)

    def prepare_options(options) do
      settings = %OptionSettings{
        option_settings: %{
          verbose: %OptionValue{option: :verbose, default: :auto},
          restart_type: %OptionValue{option: :restart_type, default: Application.get_env(:noizu_simple_pool, :pool_restart_type, :transient)},
          max_restarts: %OptionValue{option: :max_restarts, default: Application.get_env(:noizu_simple_pool, :pool_max_restarts, @default_max_restarts)},
          max_seconds: %OptionValue{option: :max_seconds, default: Application.get_env(:noizu_simple_pool, :pool_max_seconds, @default_max_seconds)},
          strategy: %OptionValue{option: :strategy, default: Application.get_env(:noizu_simple_pool, :pool_strategy, @default_strategy)}
        }
      }

      OptionSettings.expand(settings, options)
    end
  end

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.WorkerSupervisor.Layer2Behaviour.Default)
    option_settings = implementation.prepare_options(options)
    _options = option_settings.effective_options
    #@TODO - use real options.
    message_processing_provider = Noizu.SimplePool.V2.MessageProcessingBehaviour.DefaultProvider

    quote do
      @behaviour Noizu.SimplePool.V2.WorkerSupervisor.Layer2Behaviour
      use Supervisor
      require Logger

      @implementation unquote(implementation)

      #----------------------------------------
      @options :override
      @option_settings :override
      use Noizu.SimplePool.V2.SettingsBehaviour.Inherited, unquote([option_settings: option_settings, depth: 2])
      use unquote(message_processing_provider), unquote(option_settings)
      #----------------------------------------

      #-----------
      #
      #-----------
      @doc """

      """
      def child(ref, context) do
        %{
          id: ref,
          start: {pool_worker(), :start_link, [ref, context]},
          restart: @options.restart_type,
        }
      end

      @doc """

      """
      def child(ref, params, context) do
        %{
          id: ref,
          start: {pool_worker(), :start_link, [ref, params, context]},
          restart: @options.restart_type,
        }
      end

      @doc """

      """
      def child(ref, params, context, options) do
        restart = options[:restart] || @options.restart_type
        %{
          id: ref,
          start: {pool_worker(), :start_link, [ref, params, context]},
          restart: restart,
        }
      end

      #-----------
      #
      #-----------
      @doc """

      """
      def start_link(definition, context) do
        verbose() && Logger.info(fn -> {banner("#{__MODULE__}.start_link"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
        Supervisor.start_link(__MODULE__, [definition, context], [{:name, __MODULE__}])
      end

      #-----------
      #
      #-----------
      @doc """

      """
      def init([_definition, context]) do
        verbose() && Logger.info(fn -> {banner("#{__MODULE__} INIT", "args: #{inspect context}"), Noizu.ElixirCore.CallingContext.metadata(context) } end)
        Supervisor.init([], [{:strategy,  @options.strategy}, {:max_restarts, @options.max_restarts}, {:max_seconds, @options.max_seconds}])
      end

      defoverridable [
        start_link: 2,
        child: 2,
        child: 3,
        child: 4,
        init: 1,
      ]

    end # end quote
  end #end __using__
end
