defmodule Noizu.SimplePool.WorkerSupervisorBehaviour do
  alias Noizu.SimplePool.OptionSettings
  alias Noizu.SimplePool.OptionValue
  alias Noizu.SimplePool.OptionList

  @callback start_link() :: any
  @callback child(any) :: any
  @callback child(any, any) :: any
  @callback init(any) :: any

  @methods([:start_link, :child, :init])

  @features([:auto_identifier, :lazy_load, :asynch_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache])
  @default_features([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check])

  @default_max_seconds(5)
  @default_max_restarts(1000)
  @default_strategy(:one_for_one)

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        features: %OptionList{option: :features, default: Application.get_env(Noizu.SimplePool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: Application.get_env(Noizu.SimplePool, :verbose, false)},

        max_restarts: %OptionValue{option: :max_restarts, default: Application.get_env(Noizu.SimplePool, :pool_max_restarts, @default_max_restarts)},
        max_seconds: %OptionValue{option: :max_seconds, default: Application.get_env(Noizu.SimplePool, :pool_max_seconds, @default_max_seconds)},
        strategy: %OptionValue{option: :strategy, default: Application.get_env(Noizu.SimplePool, :pool_strategy, @default_strategy)}
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
      #@behaviour Noizu.SimplePool.WorkerSupervisorBehaviour
      #@before_compile unquote(__MODULE__)
      @base Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
      @worker Module.concat([@base, "Worker"])
      use Supervisor
      import unquote(__MODULE__)
      require Logger

      def option_settings do
        unquote(Macro.escape(option_settings))
      end


    # @start_link
    if (unquote(required.start_link)) do
      def start_link do
        if unquote(verbose) do
          @base.banner("#{__MODULE__}.start_link") |> Logger.info()
        end
        Supervisor.start_link(__MODULE__, [], [{:name, __MODULE__}])
      end
    end # end start_link

    # @child
    if (unquote(required.child)) do
      def child(ref, _context) do
        worker(@worker, [ref], [id: ref])
      end

      def child(ref, params, context) do
        worker(@worker, [params], [id: ref])
      end
    end # end child

    # @init
    if (unquote(required.init)) do
      def init(any) do
        if (unquote(verbose)) do
          Noizu.SimplePool.Behaviour.banner("#{__MODULE__} INIT", "args: #{inspect any}") |> Logger.info()
        end
        supervise([], [{:strategy, unquote(strategy)}, {:max_restarts, unquote(max_restarts)}, {:max_seconds, unquote(max_seconds)}])
      end
    end # end init


    end # end quote
  end #end __using__

  #defmacro __before_compile__(_env) do
  #  quote do
  #  end # end quote
  #end # end __before_compile__


end
