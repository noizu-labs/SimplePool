#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Behaviour do
  @callback pool() :: module
  @callback pool_worker_supervisor() :: module
  @callback pool_server() :: module
  @callback pool_supervisor() :: module
  @callback pool_worker() :: module
  @callback banner(String.t) :: String.t
  @callback banner(String.t, String.t) :: String.t
  @callback meta() :: Map.t
  @callback meta(Map.t) :: Map.t
  @callback meta_init() :: Map.t
  @callback options() :: Map.t
  @callback option_settings() :: Map.t

  defmacro __using__(options) do
    implementation = Keyword.get(options || [], :implementation, Noizu.SimplePool.V2.Pool.DefaultImplementation)
    option_settings = implementation.prepare_options(Macro.expand(options, __CALLER__))
    options = option_settings.effective_options
    default_modules = options.default_modules
    max_supervisors = options.max_supervisors
    quote do
      require Logger
      @behaviour Noizu.SimplePool.V2.Behaviour
      @implementation unquote(implementation)

      @parent unquote(__MODULE__)
      @module __MODULE__


      @module_str "#{@module}"

      @pool_worker_state_entity @implementation.pool_worker_state_entity(@module, unquote(options.worker_state_entity))

      @max_supervisors unquote(max_supervisors)
      @options unquote(Macro.escape(options))
      @option_settings unquote(Macro.escape(option_settings))

      # Pool Members
      @pool @implementation.pool(@module)
      @pool_worker_supervisor @implementation.pool_worker_supervisor(@module)
      @pool_server @implementation.pool_server(@module)
      @pool_worker @implementation.pool_worker(@module)
      @pool_supervisor @implementation.pool_supervisor(@module) # @module

      @meta_key Module.concat(@module, "Meta")


      @doc """
      Current Pool
      """
      def pool(), do: @pool

      @doc """
      Pool's Worker Supervisor.
      """
      def pool_worker_supervisor(), do: @pool_worker_supervisor

      @doc """
      Pool's Server
      """
      def pool_server(), do: @pool_server

      @doc """
      Pool's top level supervisor.
      """
      def pool_supervisor(), do: @pool_supervisor

      @doc """
      Pool's worker module.
      """
      def pool_worker(), do: @pool_worker

      @doc """
      Pool's worker state entity.
      """
      def pool_worker_state_entity(), do: @pool_worker_state_entity

      @doc """
      Banner Text Output Helper.
      """
      def banner(msg), do: banner(@module_str, msg)
      defdelegate banner(header, msg), to: @implementation

      @doc """
        key used for persisting meta information.
      """
      def meta_key(), do: @meta_key

      @doc """
      Runtime meta/book keeping data for pool.
      """
      def meta(), do: _imp_meta(@module)
      defdelegate _imp_meta(module), to: @implementation, as: :meta

      @doc """
      Append new entries to meta data (internally a map merge is performed).
      """
      def meta(update), do: _imp_meta(@module, update)
      defdelegate _imp_meta(module, update), to: @implementation, as: :meta

      @doc """
      Initialize meta data for this pool.
      """
      def meta_init(), do: _imp_meta_init(@module)
      defdelegate _imp_meta_init(module), to: @implementation, as: :meta_init

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
        banner: 1,
        banner: 2,
        meta_key: 0,
        meta: 0,
        meta: 1,
        meta_init: 0,
        options: 0,
        option_settings: 0,
      ]

      if (unquote(default_modules.worker)) do
        defmodule Worker do
          use Noizu.SimplePool.WorkerBehaviour, unquote(options.worker_options)
        end
      end

      if (unquote(default_modules.server)) do
        defmodule Server do
          use Noizu.SimplePool.V2.ServerBehaviour, unquote(options.server_options)
          def lazy_load(state), do: state
        end
      end

      if (unquote(default_modules.worker_supervisor)) do
        module = __MODULE__
        for i <- 1 .. @max_supervisors do
          defmodule :"#{module}.WorkerSupervisor_S#{i}" do
            use Noizu.SimplePool.V2.WorkerSupervisorBehaviour, unquote(options.worker_supervisor_options)
          end
        end
      end

      if (unquote(default_modules.pool_supervisor)) do
        defmodule PoolSupervisor do
          use Noizu.SimplePool.V2.PoolSupervisorBehaviour, unquote(options.pool_supervisor_options)
        end
      end
    end # end quote
  end #end __using__
end
