#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.SettingsBehaviour do
  @moduledoc """
    The Noizu.SimplePool.V2.Behaviour provides the entry point for Worker Pools.
    The developer will define a pool such as ChatRoomPool that uses the Noizu.SimplePool.V2.Behaviour Implementation
    before going on to define worker and server implementations.

    The module is relatively straight forward, it provides methods to get pool information (pool worker, pool supervisor)
    compile options, runtime settings (via the FastGlobal library and our meta function).
  """

  # @deprecated
  @callback base() :: module

  @callback pool() :: module
  @callback pool_worker_supervisor() :: module
  @callback pool_server() :: module
  @callback pool_supervisor() :: module
  @callback pool_worker() :: module
  @callback pool_monitor() :: module

  @callback banner(String.t) :: String.t
  @callback banner(String.t, String.t) :: String.t

  @callback verbose() :: Map.t

  @callback pool_worker_state_entity() :: module

  @callback meta() :: Map.t
  @callback meta(Map.t) :: Map.t
  @callback meta_init() :: Map.t

  @callback options() :: Map.t
  @callback option_settings() :: Map.t

  defmodule Default do
    require Logger

    def wait_for_condition(condition, timeout) do
      cond do
        timeout == :infinity -> wait_for_condition_inner(condition, timeout)
        is_integer(timeout) ->  wait_for_condition_inner(condition, :os.system_time(:millisecond) + timeout)
      end
    end

    def wait_for_condition_inner(condition, timeout) do
      case condition.() do
        true -> :ok
        :ok -> :ok
        {:ok, details} -> {:ok, details}
        e ->
          t =:os.system_time(:millisecond)
         if (t < timeout) do
           Process.sleep( min(max(50, div((timeout - t), 60)), 500))
           wait_for_condition_inner(condition, timeout)
         else
           {:timeout, e}
         end
      end
    end



    @doc """
    Return a banner string.
    ------------- Example -----------
    Multi-Line
    Banner
    ---------------------------------
    """
    def banner(header, msg) do
      header = cond do
        is_bitstring(header) -> header
        is_atom(header) -> "#{header}"
        true -> "#{inspect header}"
      end

      msg = cond do
        is_bitstring(msg) -> msg
        is_atom(msg) -> "#{msg}"
        true -> "#{inspect msg}"
      end

      header_len = String.length(header)
      len = 120

      sub_len = div(header_len, 2)
      rem = rem(header_len, 2)

      l_len = 59 - sub_len
      r_len = 59 - sub_len - rem

      char = "*"

      lines = String.split(msg, "\n", trim: true)

      top = "\n#{String.duplicate(char, l_len)} #{header} #{String.duplicate(char, r_len)}"
      bottom = String.duplicate(char, len) <> "\n"
      middle = for line <- lines do
        "#{char} " <> line
      end
      Enum.join([top] ++ middle ++ [bottom], "\n")
    end



    @doc """
    Return Meta Information for specified module.
    """
    def meta(module) do
      case FastGlobal.get(module.meta_key(), :no_entry) do
        :no_entry ->
          update = module.meta_init()
          module.meta(update)
          update
        v = %{} -> v
      end
    end

    @doc """
    Update Meta Information for module.
    """
    def meta(module, update) do
      if Semaphore.acquire({{:meta, :write}, module}, 1) do
        existing = case FastGlobal.get(module.meta_key(), :no_entry) do
          :no_entry -> module.meta_init()
          v -> v
        end
        update = Map.merge(existing, update)
        FastGlobal.put(module.meta_key(), update)
        update
      else
        false
      end
    end


    @doc """
    Initial Meta Information for Module.
    """
    def meta_init(module, _arguments \\ %{}) do
      # Grab effective options
      options = module.options()

      # meta variables

      max_restarts = options[:max_restarts] || 1_000_000
      max_seconds = options[:max_seconds] || 1
      strategy = options[:strategy] || :one_for_one
      auto_load = Enum.member?(options[:features] || [], :auto_load)
      async_load = Enum.member?(options[:features] || [], :async_load)


      response = %{
        verbose: :pending,
        stand_alone: :pending,
        max_restarts: max_restarts,
        max_seconds: max_seconds,
        strategy: strategy,
        auto_load: auto_load,
        async_load: async_load,
        featuers: MapSet.new(options[:features] || [])
      }

      # Base vs. Inherited Specific
      if (module.pool() == module) do
        verbose = if (options[:verbose] == :auto), do: Application.get_env(:noizu_simple_pool, :verbose, false), else: options[:verbose]
        stand_alone = module.stand_alone()
        %{response| verbose: verbose, stand_alone: stand_alone}
      else
        verbose = if (options[:verbose] == :auto), do: module.pool().verbose(), else: options[:verbose]
        stand_alone = module.pool().stand_alone()
        %{response| verbose: verbose, stand_alone: stand_alone}
      end
    end

    def pool_worker_state_entity(pool, :auto), do: Module.concat(pool, "WorkerStateEntity")
    def pool_worker_state_entity(_pool, worker_state_entity), do: worker_state_entity




    def profile_start(%{meta: _} = state, profile \\ :default) do
      state
      |> update_in([Access.key(:meta), :profiler], &(&1 || %{}))
      |> put_in([Access.key(:meta), :profiler, profile], %{start: :os.system_time(:millisecond)})
    end

    def profile_end(%{meta: _} = state, profile, prefix, options) do
      state = state
              |> update_in([Access.key(:meta), :profiler], &(&1 || %{}))
              |> update_in([Access.key(:meta), :profiler, profile], &(&1 || %{}))
              |> put_in([Access.key(:meta), :profiler, profile, :end], :os.system_time(:millisecond))



      interval = (state.meta.profiler[profile][:end]) - (state.meta.profiler[profile][:start] || 0)
      cond do
        state.meta.profiler[profile][:start] == nil -> Logger.warn(fn -> "[#{prefix} prof] profile_start not invoked for #{profile}" end)
        options[:error] && interval >= options[:error] ->
          options[:log] && Logger.error(fn -> "[#{prefix} prof] #{profile} exceeded #{options[:error]} milliseconds @#{interval}" end)
          _state = state
                  |> put_in([Access.key(:meta), :profiler, profile, :flag], :error)
        options[:warn] && interval >= options[:warn] ->
          options[:log] && Logger.warn(fn -> "[#{prefix} prof] #{profile} exceeded #{options[:warn]} milliseconds @#{interval}" end)
          _state = state
                  |> put_in([Access.key(:meta), :profiler, profile, :flag], :warn)
        options[:info] && interval >= options[:info] ->
          options[:log] && Logger.info(fn -> "[#{prefix} prof] #{profile} exceeded #{options[:info]} milliseconds @#{interval}" end)
          _state = state
                  |> put_in([Access.key(:meta), :profiler, profile, :flag], :info)
        :else ->
          _state = state
                  |> put_in([Access.key(:meta), :profiler, profile, :flag], :green)
      end
    end


    def expand_table(module, table, name) do
      # Apply Schema Naming Convention if not specified
      if (table == :auto) do
        path = Module.split(module)
        root_table = Application.get_env(:noizu_scaffolding, :default_database, Module.concat([List.first(path), "Database"]))
                     |> Module.split()
        inner_path = Enum.slice(path, 1..-1)
        Module.concat(root_table ++ inner_path ++ [name])
      else
        table
      end
    end

  end

  defmodule Base do
    defmacro __using__(opts) do
      option_settings = Macro.expand(opts[:option_settings], __CALLER__)
      options = option_settings.effective_options
      pool_worker_state_entity = Map.get(options, :worker_state_entity, :auto)
      stand_alone = opts[:stand_alone] || false

      #dispatch_table = options.dispatch_table
      #dispatch_monitor_table = options.dispatch_monitor_table
      #registry_options = options.registry_options


      service_manager = options.service_manager
      node_manager = options.node_manager



      quote do
        @behaviour Noizu.SimplePool.V2.SettingsBehaviour
        @module __MODULE__
        @module_str "#{@module}"
        @meta_key Module.concat(@module, Meta)

        @stand_alone unquote(stand_alone)

        @pool @module
        @task_supervisor Module.concat([@pool, "TaskSupervisor"])
        @pool_server Module.concat([@pool, "Server"])
        @pool_supervisor Module.concat([@pool, "PoolSupervisor"])
        @pool_worker_supervisor Module.concat([@pool, "WorkerSupervisor"])
        @pool_worker Module.concat([@pool, "Worker"])
        @pool_monitor Module.concat([@pool, "Monitor"])
        @pool_registry Module.concat([@pool, "Registry"])

        @node_manager unquote(node_manager)
        @service_manager unquote(service_manager)

        @pool_dispatch_table Noizu.SimplePool.V2.SettingsBehaviour.Default.expand_table(@pool, unquote(options.dispatch_table), DispatchTable)

        @options unquote(Macro.escape(options))
        @option_settings unquote(Macro.escape(option_settings))

        @pool_worker_state_entity Noizu.SimplePool.V2.SettingsBehaviour.Default.pool_worker_state_entity(@pool, unquote(pool_worker_state_entity))

        @short_name Module.split(__MODULE__) |> Enum.slice(-1..-1) |> Module.concat()


        defdelegate wait_for_condition(condition, timeout \\ :infinity), to: Noizu.SimplePool.V2.SettingsBehaviour.Default

        def short_name(), do: @short_name

        def profile_start(%{meta: _} = state, profile \\ :default) do
          Noizu.SimplePool.V2.SettingsBehaviour.Default.profile_start(state, profile)
        end

        def profile_end(%{meta: _} = state, profile \\ :default, opts \\ %{info: 100, warn: 300, error: 700, log: true}) do
          Noizu.SimplePool.V2.SettingsBehaviour.Default.profile_end(state, profile, short_name(), opts)
        end

        # @deprecated
        def base, do: @pool
        def pool, do: @pool

        def task_supervisor, do: @task_supervisor
        def pool_server, do: @pool_server
        def pool_supervisor, do: @pool_supervisor
        def pool_monitor, do: @pool_monitor
        def pool_worker_supervisor, do: @pool_worker_supervisor
        def pool_worker, do: @pool_worker
        def pool_worker_state_entity, do: @pool_worker_state_entity
        def pool_dispatch_table(), do: @pool_dispatch_table
        def pool_registry(), do: @pool_registry

        def node_manager(), do: @node_manager
        def service_manager(), do: @service_manager

        def banner(msg), do: banner(@module, msg)
        defdelegate banner(header, msg), to: Noizu.SimplePool.V2.SettingsBehaviour.Default

        @doc """
        Get verbosity level.
        """
        def verbose(), do: meta()[:verbose]

        @doc """
          key used for persisting meta information. Defaults to __MODULE__.Meta
        """
        def meta_key(), do: @meta_key


        @doc """
        Runtime meta/book keeping data for pool.
        """
        def meta(), do: Noizu.SimplePool.V2.SettingsBehaviour.Default.meta(@module)

        @doc """
        Append new entries to meta data (internally a map merge is performed).
        """
        def meta(update), do: Noizu.SimplePool.V2.SettingsBehaviour.Default.meta(@module, update)

        @doc """
        Initial Meta Information for Module.
        """
        def meta_init(), do: Noizu.SimplePool.V2.SettingsBehaviour.Default.meta_init(@module, %{stand_alone: @stand_alone})

        @doc """
        retrieve effective compile time options/settings for pool.
        """
        def options(), do: @options

        @doc """
        retrieve extended compile time options information for this pool.
        """
        def option_settings(), do: @option_settings


        defoverridable [
          wait_for_condition: 2,
          base: 0,
          pool: 0,
          pool_worker_supervisor: 0,
          task_supervisor: 0,
          pool_server: 0,
          pool_supervisor: 0,
          pool_worker: 0,
          pool_monitor: 0,
          pool_worker_state_entity: 0,
          banner: 1,
          banner: 2,
          verbose: 0,
          meta_key: 0,
          meta: 0,
          meta: 1,
          meta_init: 0,
          options: 0,
          option_settings: 0,
        ]
      end
    end
  end

  defmodule Inherited do
    defmacro __using__(opts) do
      depth = opts[:depth] || 1
      option_settings = Macro.expand(opts[:option_settings], __CALLER__)
      options = option_settings.effective_options

      pool_worker_state_entity = Map.get(options, :worker_state_entity, :auto)
      stand_alone = opts[:stand_alone] || false

      quote do
        @depth unquote(depth)
        @behaviour Noizu.SimplePool.V2.SettingsBehaviour
        @parent Module.split(__MODULE__) |> Enum.slice(0.. -2) |> Module.concat()
        @pool Module.split(__MODULE__) |> Enum.slice(0.. -(@depth + 1)) |> Module.concat()
        @module __MODULE__
        @module_str "#{@module}"
        @meta_key Module.concat(@module, Meta)
        @stand_alone unquote(stand_alone)
        @options unquote(Macro.escape(options))
        @option_settings unquote(Macro.escape(option_settings))

        # may not match pool_worker_state_entity
        @pool_worker_state_entity Noizu.SimplePool.V2.SettingsBehaviour.Default.pool_worker_state_entity(@pool, unquote(pool_worker_state_entity))


        @short_name Module.split(__MODULE__) |> Enum.slice(-2..-1) |> Module.concat()

        def short_name(), do: @short_name

        def profile_start(%{meta: _} = state, profile \\ :default) do
          Noizu.SimplePool.V2.SettingsBehaviour.Default.profile_start(state, profile)
        end

        def profile_end(%{meta: _} = state, profile \\ :default, opts \\ %{info: 100, warn: 300, error: 700, log: true}) do
          Noizu.SimplePool.V2.SettingsBehaviour.Default.profile_end(state, profile, short_name(), opts)
        end

        defdelegate wait_for_condition(condition, timeout \\ :infinity), to: Noizu.SimplePool.V2.SettingsBehaviour.Default

        # @deprecated
        defdelegate base(), to: @parent


        defdelegate pool(), to: @pool
        defdelegate pool_worker_supervisor(), to: @pool
        defdelegate task_supervisor(), to: @pool
        defdelegate pool_server(), to: @pool
        defdelegate pool_supervisor(), to: @pool
        defdelegate pool_worker(), to: @pool
        defdelegate pool_worker_state_entity(), to: @pool
        defdelegate pool_monitor(), to: @pool

        defdelegate pool_dispatch_table(), to: @pool
        defdelegate pool_registry(), to: @pool


        defdelegate node_manager(), to: @pool
        defdelegate service_manager(), to: @pool


        def banner(msg), do: banner(@module, msg)
        defdelegate banner(header, msg), to: Noizu.SimplePool.V2.SettingsBehaviour.Default

        @doc """
        Get verbosity level.
        """
        def verbose(), do: meta()[:verbose]

        @doc """
          key used for persisting meta information. Defaults to __MODULE__.Meta
        """
        def meta_key(), do: @meta_key


        @doc """
        Runtime meta/book keeping data for pool.
        """
        def meta(), do: Noizu.SimplePool.V2.SettingsBehaviour.Default.meta(@module)

        @doc """
        Append new entries to meta data (internally a map merge is performed).
        """
        def meta(update), do: Noizu.SimplePool.V2.SettingsBehaviour.Default.meta(@module, update)

        @doc """
        Initial Meta Information for Module.
        """
        def meta_init(), do: Noizu.SimplePool.V2.SettingsBehaviour.Default.meta_init(@module, %{stand_alone: @stand_alone})

        @doc """
        retrieve effective compile time options/settings for pool.
        """
        def options(), do: @options

        @doc """
        retrieve extended compile time options information for this pool.
        """
        def option_settings(), do: @option_settings

        defoverridable [
          wait_for_condition: 2,
          base: 0,
          pool: 0,
          pool_worker_supervisor: 0,
          task_supervisor: 0,
          pool_server: 0,
          pool_supervisor: 0,
          pool_worker: 0,
          pool_monitor: 0,
          pool_worker_state_entity: 0,
          banner: 1,
          banner: 2,
          verbose: 0,
          meta_key: 0,
          meta: 0,
          meta: 1,
          meta_init: 0,
          options: 0,
          option_settings: 0,
        ]
      end
    end
  end

end
