#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.PoolSettingsBehaviour do
  @moduledoc """
    The Noizu.SimplePool.V2.Behaviour provides the entry point for Worker Pools.
    The developer will define a pool such as ChatRoomPool that uses the Noizu.SimplePool.V2.Behaviour Implementation
    before going on to define worker and server implementations.

    The module is relatively straight forward, it provides methods to get pool information (pool worker, pool supervisor)
    compile options, runtime settings (via the FastGlobal library and our meta function).
  """

  @callback pool() :: module
  @callback pool_worker_supervisor() :: module
  @callback pool_server() :: module
  @callback pool_supervisor() :: module
  @callback pool_worker() :: module

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

    def pool_worker_state_entity(pool, :auto), do: Module.concat(pool, "WorkerStateEntity")
    def pool_worker_state_entity(_pool, worker_state_entity), do: worker_state_entity
  end

  defmodule Base do
    defmacro __using__(opts) do
      option_settings = Macro.expand(opts[:option_settings], __CALLER__)
      options = option_settings.effective_options

      pool_worker_state_entity = Map.get(options, :worker_state_entity, :auto)


      quote do
        @behaviour Noizu.SimplePool.V2.PoolSettingsBehaviour

        @module __MODULE__
        @module_str "#{@module}"
        @meta_key Module.concat(@module, Meta)

        @pool @module
        @pool_worker_supervisor Module.concat([@pool, "WorkerSupervisor"])
        @pool_server Module.concat([@pool, "Server"])
        @pool_worker Module.concat([@pool, "Worker"])
        @pool_supervisor Module.concat([@pool, "PoolSupervisor"])

        @options unquote(Macro.escape(options))
        @option_settings unquote(Macro.escape(option_settings))

        @pool_worker_state_entity Noizu.SimplePool.V2.PoolSettingsBehaviour.Default.pool_worker_state_entity(@pool, unquote(pool_worker_state_entity))

        def pool, do: @pool
        def pool_worker_supervisor, do: @pool_worker_supervisor
        def pool_server, do: @pool_server
        def pool_supervisor, do: @pool_supervisor
        def pool_worker, do: @pool_worker
        def pool_worker_state_entity, do: @pool_worker_state_entity

        def banner(msg), do: banner(@module, msg)
        defdelegate banner(header, msg), to: Noizu.SimplePool.V2.PoolSettingsBehaviour.Default

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
        def meta(), do: Noizu.SimplePool.V2.PoolSettingsBehaviour.Default.meta(@module)

        @doc """
        Append new entries to meta data (internally a map merge is performed).
        """
        def meta(update), do: Noizu.SimplePool.V2.PoolSettingsBehaviour.Default.meta(@module, update)

        @doc """
        Initial Meta Information for Module.
        """
        def meta_init(), do: %{}


        @doc """
        retrieve effective compile time options/settings for pool.
        """
        def options(), do: @options

        @doc """
        retrieve extended compile time options information for this pool.
        """
        def option_settings(), do: @option_settings


        defoverridable [
          pool: 0,
          pool_worker_supervisor: 0,
          pool_server: 0,
          pool_supervisor: 0,
          pool_worker: 0,
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


      quote do
        @depth unquote(depth)
        @behaviour Noizu.SimplePool.V2.PoolSettingsBehaviour
        @parent Module.split(__MODULE__) |> Enum.slice(0.. -2) |> Module.concat()
        @pool Module.split(__MODULE__) |> Enum.slice(0.. -(@depth + 1)) |> Module.concat()
        @module __MODULE__
        @module_str "#{@module}"
        @meta_key Module.concat(@module, Meta)

        @options unquote(Macro.escape(options))
        @option_settings unquote(Macro.escape(option_settings))

        # may not match pool_worker_state_entity
        @pool_worker_state_entity Noizu.SimplePool.V2.PoolSettingsBehaviour.Default.pool_worker_state_entity(@pool, unquote(pool_worker_state_entity))

        defdelegate pool(), to: @parent
        defdelegate pool_worker_supervisor(), to: @parent
        defdelegate pool_server(), to: @parent
        defdelegate pool_supervisor(), to: @parent
        defdelegate pool_worker(), to: @parent
        defdelegate pool_worker_state_entity(), to: @parent

        def banner(msg), do: banner(@module, msg)
        defdelegate banner(header, msg), to: Noizu.SimplePool.V2.PoolSettingsBehaviour.Default

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
        def meta(), do: Noizu.SimplePool.V2.PoolSettingsBehaviour.Default.meta(@module)

        @doc """
        Append new entries to meta data (internally a map merge is performed).
        """
        def meta(update), do: Noizu.SimplePool.V2.PoolSettingsBehaviour.Default.meta(@module, update)

        @doc """
        Initial Meta Information for Module.
        """
        def meta_init(), do: %{}

        @doc """
        retrieve effective compile time options/settings for pool.
        """
        def options(), do: @options

        @doc """
        retrieve extended compile time options information for this pool.
        """
        def option_settings(), do: @option_settings

        defoverridable [
          pool: 0,
          pool_worker_supervisor: 0,
          pool_server: 0,
          pool_supervisor: 0,
          pool_worker: 0,
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