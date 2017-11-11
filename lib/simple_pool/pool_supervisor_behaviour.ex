defmodule Noizu.SimplePool.PoolSupervisorBehaviour do
  alias Noizu.SimplePool.OptionSettings
  alias Noizu.SimplePool.OptionValue
  alias Noizu.SimplePool.OptionList
  require Logger
  @callback option_settings() :: Map.t
  @callback start_link() :: any
  @callback start_children(any) :: any

  @methods([:start_link, :start_children, :init])

  @features([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection])
  @default_features([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection])

  @default_max_seconds(5)
  @default_max_restarts(1000)
  @default_strategy(:one_for_one)

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: Application.get_env(:noizu_simple_pool, :verbose, false)},

        max_restarts: %OptionValue{option: :max_restarts, default: Application.get_env(:noizu_simple_pool, :pool_max_restarts, @default_max_restarts)},
        max_seconds: %OptionValue{option: :max_seconds, default: Application.get_env(:noizu_simple_pool, :pool_max_seconds, @default_max_seconds)},
        strategy: %OptionValue{option: :strategy, default: Application.get_env(:noizu_simple_pool, :pool_strategy, @default_strategy)}
      }
    }

    initial = OptionSettings.expand(settings, options)
    modifications = Map.put(initial.effective_options, :required, List.foldl(@methods, %{}, fn(x, acc) -> Map.put(acc, x, initial.effective_options.only[x] && !initial.effective_options.override[x]) end))
    %OptionSettings{initial| effective_options: Map.merge(initial.effective_options, modifications)}
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
      import unquote(__MODULE__)

      def option_settings do
        unquote(Macro.escape(option_settings))
      end

      # @start_link
      if (unquote(required.start_link)) do
        def start_link do
          if unquote(verbose) do
            @base.banner("#{__MODULE__}.start_link") |> Logger.info
          end

          case Supervisor.start_link(__MODULE__, [], [{:name, __MODULE__}]) do
            {:ok, sup} ->
              Logger.info "#{__MODULE__}.start_link Supervisor Not Started. #{inspect sup}"
              start_children(__MODULE__)
              {:ok, sup}
            {:error, {:already_started, sup}} ->
              Logger.info "#{__MODULE__}.start_link Supervisor Already Started. Handling unexected state.  #{inspect sup}"
              start_children(__MODULE__)
              {:ok, sup}
          end
        end
      end # end start_link

      # @start_children
      if (unquote(required.start_children)) do
        def start_children(sup) do
          if unquote(verbose) do
            Noizu.SimplePool.Behaviour.banner("#{__MODULE__} START_CHILDREN",
            " Options: #{inspect unquote(Macro.escape(options))}\n"  <>
            " #{__MODULE__}\n"  <>
            " worker_supervisor: #{@worker_supervisor}\n"  <>
            " worker_server: #{@pool_server}\n")
            |> Logger.info()
          end

          case Supervisor.start_child(sup, supervisor(@worker_supervisor, [], [])) do
            {:ok, pool_supervisor} ->

              case Supervisor.start_child(sup, worker(@pool_server, [@worker_supervisor], [])) do
                {:ok, pid} -> {:ok, pid}
                {:error, {:already_started, process2_id}} ->
                  Supervisor.restart_child(__MODULE__, process2_id)
                error ->
                  Logger.error "#{__MODULE__}.start_children(1) #{inspect @worker_supervisor} Already Started. Handling unexepected state.
                  #{inspect error}
                  "
              end

            {:error, {:already_started, process_id}} ->
              case Supervisor.restart_child(__MODULE__, process_id) do
                {:ok, pid} ->
                  case Supervisor.start_child(__MODULE__, worker(@pool_server, [@worker_supervisor], [])) do
                    {:ok, pid} -> {:ok, pid}
                    {:error, {:already_started, process2_id}} ->
                      Supervisor.restart_child(__MODULE__, process2_id)
                    error ->
                      Logger.error "#{__MODULE__}.start_children(2) #{inspect @worker_supervisor} Already Started. Handling unexepected state.
                      #{inspect error}
                      "
                  end
                error ->
                  Logger.info "#{__MODULE__}.start_children(3) #{inspect @worker_supervisor} Already Started. Handling unexepected state.
                  #{inspect error}
                  "
              end

            error ->
              Logger.info "#{__MODULE__}.start_children(4) #{inspect @worker_supervisor} Already Started. Handling unexepected state.
              #{inspect error}
              "
          end

          # Lazy Load Children Load Children
          @pool_server.load(nil, nil)
        end
      end # end start_children


      # @init
      if (unquote(required.init)) do
        def init(arg) do
          if unquote(verbose) do
            Noizu.SimplePool.Behaviour .banner("#{__MODULE__} INIT", "args: #{inspect arg}") |> Logger.info()
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
        Logger.warn("Uncaught handle_call to #{__MODULE__} . . . #{inspect uncaught}")
        {:noreply, state}
      end

      def handle_cast(uncaught, state) do
        Logger.warn("Uncaught handle_cast to #{__MODULE__} . . . #{inspect uncaught}")
        {:noreply, state}
      end

      def handle_info(uncaught, state) do
        Logger.warn("Uncaught handle_info to #{__MODULE__} . . . #{inspect uncaught}")
        {:noreply, state}
      end
    end # end quote
  end # end __before_compile__

end
