#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.PoolSupervisorBehaviour do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList
  require Logger
  @callback option_settings() :: Map.t
  @callback start_link() :: any
  @callback start_children(any) :: any

  @methods ([:start_link, :start_children, :init])

  @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection])
  @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection])

  @default_max_seconds (5)
  @default_max_restarts (100_000)
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

  def default_start_link(verbose, base, mod) do
    if verbose do
       Logger.info(fn -> base.banner("#{mod}.start_link") end)
    end

    case Supervisor.start_link(mod, [], [{:name, mod}]) do
      {:ok, sup} ->
        Logger.info(fn ->  "#{mod}.start_link Supervisor Not Started. #{inspect sup}" end)
        mod.start_children(mod)
        {:ok, sup}
      {:error, {:already_started, sup}} ->
        Logger.info(fn -> "#{mod}.start_link Supervisor Already Started. Handling unexected state.  #{inspect sup}"  end)
        mod.start_children(mod)
        {:ok, sup}
    end
  end


  def default_start_children(verbose, base, worker_supervisor, pool_server, mod, sup) do
    if verbose do
      Logger.info(fn ->
        base.banner(
          """
          #{mod} START_CHILDREN
          Options: #{inspect mod.options()}
          worker_supervisor: #{worker_supervisor}
          worker_server: #{pool_server}
          """)
      end)
    end

    case Supervisor.start_child(sup, mod.supervisor(worker_supervisor, [], [])) do
      {:ok, pool_supervisor} ->

        case Supervisor.start_child(sup, mod.worker(pool_server, [worker_supervisor], [])) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, process2_id}} ->
            Supervisor.restart_child(__MODULE__, process2_id)
          error ->
            Logger.error(fn ->
              """

              #{__MODULE__}.start_children(1) #{inspect worker_supervisor} Already Started. Handling unexepected state.
              #{inspect error}
              """
            end)
        end

      {:error, {:already_started, process_id}} ->
        case Supervisor.restart_child(__MODULE__, process_id) do
          {:ok, pid} ->
            case Supervisor.start_child(__MODULE__, mod.worker(pool_server, [worker_supervisor], [])) do
              {:ok, pid} -> {:ok, pid}
              {:error, {:already_started, process2_id}} ->
                Supervisor.restart_child(__MODULE__, process2_id)
              error ->
                Logger.error(fn ->
                  """

                  #{__MODULE__}.start_children(2) #{inspect worker_supervisor} Already Started. Handling unexepected state.
                  #{inspect error}
                  """
                end)
            end
          error ->
            Logger.info(fn ->
              """

              #{__MODULE__}.start_children(3) #{inspect worker_supervisor} Already Started. Handling unexepected state.
              #{inspect error}
              """  end)
        end

      error ->
        Logger.info(fn ->
          """

          #{__MODULE__}.start_children(4) #{inspect worker_supervisor} Already Started. Handling unexepected state.
          #{inspect error}
          """
        end)
    end

    # Lazy Load Children Load Children
    pool_server.load(nil, nil)
  end


  defmacro __using__(options) do
    option_settings = prepare_options(options)
    options = option_settings.effective_options

    required = options.required
    max_restarts = options.max_restarts
    max_seconds = options.max_seconds
    strategy = options.strategy
    verbose = options.verbose
    quote do
      use Supervisor
      require Logger
      @behaviour Noizu.SimplePool.PoolSupervisorBehaviour
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
      @worker_supervisor Module.concat([@base, "WorkerSupervisor"])
      @pool_server Module.concat([@base, "Server"])
      @base_verbose unquote(verbose)
      import unquote(__MODULE__)

      def verbose() do
        default_verbose(@base_verbose, @base)
      end

      def options do
        unquote(Macro.escape(options))
      end

      def option_settings do
        unquote(Macro.escape(option_settings))
      end

      # @start_link
      if (unquote(required.start_link)) do
        def start_link do
          default_start_link(verbose(), @base, __MMODULE__)
        end
      end # end start_link

      # @start_children
      if (unquote(required.start_children)) do
        def start_children(sup) do
          default_start_children(verbose(), @base, @worker_supervisor, @pool_server, __MODULE__, sup)
        end
      end # end start_children


      # @init
      if (unquote(required.init)) do
        def init(arg) do
          if verbose() do
            Logger.info(fn -> Noizu.SimplePool.Behaviour.banner("#{__MODULE__} INIT", "args: #{inspect arg}") end)
          end
          supervise([], [{:strategy, unquote(strategy)}, {:max_restarts, unquote(max_restarts)}, {:max_seconds, unquote(max_seconds)}])
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
