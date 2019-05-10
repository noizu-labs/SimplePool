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

  defmodule Default do
    @moduledoc """
    Reusable functionality implemented here to reduce size of generated code.
    """
    alias Noizu.ElixirCore.OptionSettings
    alias Noizu.ElixirCore.OptionValue
    #alias Noizu.ElixirCore.OptionList
    @default_max_seconds (5)
    @default_max_restarts (1000)
    @default_strategy (:one_for_one)

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

          dynamic_supervisor: %OptionValue{option: :dynamic_supervisor, default: false, required: false},

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


      @doc """
      Initial Meta Information for Module.
      """
      def meta_init() do
        verbose_setting = case options().verbose do
          :auto -> pool().verbose()
          v -> v
        end

        leading = round(:math.floor(:math.log10(@max_supervisors))) + 1
        supervisor_by_index = Enum.map(1 .. @max_supervisors, fn(i) ->
          {i, Module.concat(__MODULE__, "Seg#{String.pad_leading("#{i}", leading, "0")}")}
        end) |> Map.new()
        available_supervisors = Map.values(supervisor_by_index)
        active_supervisors = length(available_supervisors)

        dynamic_supervisor = options().dynamic_supervisor
        %{
          active_supervisors: active_supervisors,
          available_supervisors: available_supervisors,
          supervisor_by_index: supervisor_by_index,
          dynamic_supervisor: dynamic_supervisor,
          verbose: verbose_setting,
        }
      end

      def supervisor_by_index(index), do: meta()[:supervisor_by_index][index]
      def available_supervisors(), do: meta()[:available_supervisors]
      def active_supervisors(), do: meta()[:active_supervisors]

      def group_children(group_fn) do
        Task.async_stream(available_supervisors(), fn(s) ->
                                                     children = Supervisor.which_children(s)
                                                     sg = Enum.reduce(children, %{}, fn(worker, acc) ->
                                                                                       g = group_fn.(worker)
                                                                                       if g do
                                                                                         update_in(acc, [g], &((&1 || 0) + 1))
                                                                                       else
                                                                                         acc
                                                                                       end
                                                     end)
                                                     {s, sg}
        end, timeout: 60_000, ordered: false)
        |> Enum.reduce(%{total: %{}}, fn(outcome, acc) ->
          case outcome do
            {:ok, {s, sg}} ->
              total = Enum.reduce(sg, acc.total, fn({g, c}, a) ->  update_in(a, [g], &((&1 || 0) ++ c)) end)
              acc = acc
                    |> put_in([s], sg)
                    |> put_in([:total], total)
            _ -> acc
          end
        end)
      end


      def count_children() do
        {a,s, u, w} = Task.async_stream(
                        available_supervisors(),
                        fn(s) ->
                          u = Supervisor.count_children(s)
                          {u.active, u.specs, u.supervisors, u.workers}
                        end,
                        [ordered: false, timeout: 60_000, on_timeout: :kill_task]
                      ) |> Enum.reduce({0,0,0,0}, fn(x, {acc_a, acc_s, acc_u, acc_w}) ->
          case x do
            {:ok, {a,s, u, w}} -> {acc_a + a, acc_s + s, acc_u + u, acc_w + w}
            {:exit, :timeout} -> {acc_a, acc_s, acc_u, acc_w}
            _ -> {acc_a, acc_s, acc_u, acc_w}
          end
        end)
        %{active: a, specs: s, supervisors: u, workers: w}
      end

      def current_supervisor(ref) do
        cond do
          meta()[:dynamic_supervisor] -> current_supervisor_dynamic(ref)
          true -> current_supervisor_default(ref)
        end
      end

      def current_supervisor_default(ref) do
        num_supervisors = active_supervisors()
        if num_supervisors == 1 do
          supervisor_by_index(1)
        else
          hint = pool_worker_state_entity().supervisor_hint(ref)
          pick = rem(hint, num_supervisors) + 1
          supervisor_by_index(pick)
        end
      end

      def current_supervisor_dynamic(ref) do
        num_supervisors = active_supervisors()
        if num_supervisors == 1 do
          supervisor_by_index(1)
        else
          hint = pool_worker_state_entity().supervisor_hint(ref)
          # The logic is designed so that the selected supervisor only changes for a subset of items when adding new supervisors
          # So that, for example, when going from 5 to 6 supervisors only a 6th of entries will be re-assigned to the new bucket.
          pick = Enum.reduce_while(num_supervisors .. 1, 1, fn(x, acc) ->
            n = rem(hint, x) + 1
            cond do
              n == x -> {:halt, n}
              true -> {:cont, acc}
            end
          end)

          pick = fn(hint, num_supervisors) ->
            Enum.reduce_while(num_supervisors .. 1, 1, fn(x, acc) ->
              n = rem(hint, x) + 1
              cond do
                n == x -> {:halt, n}
                true -> {:cont, acc}
              end
            end)
          end
          supervisor_by_index(pick)
        end
      end


      defoverridable [
        start_link: 2,
        init: 1,
        current_supervisor: 1,
        supervisor_by_index: 1,
        available_supervisors: 0,
        active_supervisors: 0,
        group_children: 1,
        count_children: 0,
      ]

      #==================================================
      # Generate Sub Supervisors
      #==================================================
      module = __MODULE__
      leading = round(:math.floor(:math.log10(@max_supervisors))) + 1
      for i <- 1 .. @max_supervisors do
        defmodule :"#{module}.Seg#{String.pad_leading("#{i}", leading, "0")}" do
          use unquote(layer2_provider), unquote(options[:layer2_options] || [])
        end
      end
    end # end quote
  end #end __using__
end
