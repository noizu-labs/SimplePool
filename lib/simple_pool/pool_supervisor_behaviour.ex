#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.PoolSupervisorBehaviour do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList
  require Logger
  @callback option_settings() :: Map.t
  @callback start_link(any, any) :: any
  @callback start_children(any, any, any) :: any

  @methods ([:start_link, :start_children, :init, :verbose, :options, :option_settings, :start_worker_supervisors])

  @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection])
  @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection])

  @default_max_seconds (1)
  @default_max_restarts (1_000_000)
  @default_strategy (:one_for_one)

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: :auto},

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
    verbose = options.verbose
    features = MapSet.new(options.features)

    quote do
      use Supervisor
      require Logger
      @auto_load unquote(MapSet.member?(features, :auto_load))
      @behaviour Noizu.SimplePool.PoolSupervisorBehaviour
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
      @worker_supervisor Module.concat([@base, "WorkerSupervisor"])
      @pool_server Module.concat([@base, "Server"])
      @base_verbose unquote(verbose)
      @options unquote(Macro.escape(options))
      @option_settings unquote(Macro.escape(option_settings))
      import unquote(__MODULE__)

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
        def start_link(context, definition \\ :auto) do
          if verbose() do
            Logger.info(fn -> {Noizu.SimplePool.Behaviour.banner("#{__MODULE__}.start_link", "args: #{inspect %{context: context, definition: definition}} "), Noizu.ElixirCore.CallingContext.metadata(context)} end)
          end
          case Supervisor.start_link(__MODULE__, [context], [{:name, __MODULE__}, {:restart, :permanent}]) do
            {:ok, sup} ->
              Logger.info(fn ->  {"#{__MODULE__}.start_link Supervisor Not Started. #{inspect sup}", Noizu.ElixirCore.CallingContext.metadata(context)} end)
              start_children(__MODULE__, context, definition)
              {:ok, sup}
            {:error, {:already_started, sup}} ->
              Logger.info(fn -> {"#{__MODULE__}.start_link Supervisor Already Started. Handling unexected state.  #{inspect sup}" , Noizu.ElixirCore.CallingContext.metadata(context)} end)
              start_children(__MODULE__, context, definition)
              {:ok, sup}
          end
        end
      end # end start_link

      # @start_children
      if (unquote(required.start_children)) do
        def start_children(sup, context, definition) do
          if verbose() do
            Logger.info(fn -> {
                              Noizu.SimplePool.Behaviour.banner("#{__MODULE__}.start_children",
                                  """

                                  #{__MODULE__} START_CHILDREN
                                  Options: #{inspect options()}
                                  worker_supervisor: #{@worker_supervisor}
                                  worker_server: #{@pool_server}
                                  definition: #{inspect definition}
                                  """),
                                Noizu.ElixirCore.CallingContext.metadata(context)
                              }
            end)
          end

          _o = start_worker_supervisors(sup, definition, context)

          s = case Supervisor.start_child(sup, worker(@pool_server, [:deprecated, definition, context], [restart: :permanent, max_restarts: unquote(max_restarts), max_seconds: unquote(max_seconds)])) do
            {:ok, pid} ->
              {:ok, pid}
            {:error, {:already_started, process2_id}} ->
              Supervisor.restart_child(__MODULE__, process2_id)
            error ->
              Logger.error(fn ->
                {
                  """

                  #{__MODULE__}.start_children(1) #{inspect @worker_supervisor} Already Started. Handling unexepected state.
                  #{inspect error}
                  """, Noizu.ElixirCore.CallingContext.metadata(context)}
              end)
              :error
          end
          if s != :error && @auto_load do
            spawn fn -> @pool_server.load(context, @options) end
          end
          s
        end # end start_children
      end # end if required

      if (unquote(required.start_worker_supervisors)) do
        def start_worker_supervisors(sup, definition, context) do
          supervisors = @pool_server.available_supervisors()
          for s <- supervisors do

            case Supervisor.start_child(sup, supervisor(s, [definition, context], [restart: :permanent, max_restarts: unquote(max_restarts), max_seconds: unquote(max_seconds)] )) do
              {:ok, _pool_supervisor} ->  :ok
              {:error, {:already_started, process_id}} ->
                case Supervisor.restart_child(__MODULE__, process_id) do
                  {:ok, pid} -> :ok
                  error ->
                    Logger.info(fn ->{
                                       """

                                       #{__MODULE__}.start_children(3) #{inspect s} Already Started. Handling unexepected state.
                                       #{inspect error}
                                       """, Noizu.ElixirCore.CallingContext.metadata(context)}
                    end)
                    :error
                end
              error ->
                Logger.info(fn -> {
                                    """

                                    #{__MODULE__}.start_children(4) #{inspect @worker_supervisor} Already Started. Handling unexepected state.
                                    #{inspect error}
                                    """, Noizu.ElixirCore.CallingContext.metadata(context)}
                end)
                :error
            end # end case
          end # end for
        end # end start_worker_supervisors
      end # end if required

      # @init
      if (unquote(required.init)) do
        def init([context] = arg) do
          if verbose() || true do
            Logger.warn(fn -> {Noizu.SimplePool.Behaviour.banner("#{__MODULE__} INIT", "args: #{inspect arg}"), Noizu.ElixirCore.CallingContext.metadata(context)} end)
          end
          supervise([], [{:strategy, unquote(strategy)}, {:max_restarts, unquote(max_restarts)}, {:max_seconds, unquote(max_seconds)}, {:restart, :permanent}])
        end
      end # end init

      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
      require Logger
      def handle_call(uncaught, _from, state) do
        Logger.warn(fn -> "Uncaught handle_call to #{__MODULE__} . . . #{inspect uncaught}" end)
        {:noreply, state}
      end

      def handle_cast(uncaught, state) do
        Logger.warn(fn -> "Uncaught handle_cast to #{__MODULE__} . . . #{inspect uncaught}" end)
        {:noreply, state}
      end

      def handle_info(uncaught, state) do
        Logger.warn(fn -> "Uncaught handle_info to #{__MODULE__} . . . #{inspect uncaught}" end)
        {:noreply, state}
      end
    end # end quote
  end # end __before_compile__

end