#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.InnerStateBehaviour do
  @moduledoc """
    The method provides scaffolding for Pool Worker Entities.  Such as support for calls such as shutdown, different init strategies, etc.

    @note this module is currently a duplicate of the V1 implementation
    @todo InnerStateBehaviour and WorkerBehaviour should be combined while moving the split between the Pool.Worker and the actual entity.
  """
  require Logger
  #@callback call_forwarding(call :: any, context :: any, from :: any,  state :: any, outer_state :: any) :: {atom, reply :: any, state :: any}
  @callback fetch(this :: any, options :: any, context :: any) :: {:reply, this :: any, this :: any}

  @callback load(ref :: any) ::  any
  @callback load(ref :: any, context :: any) :: any
  @callback load(ref :: any, context :: any, options :: any) :: any

  @callback terminate_hook(reason :: any,  Noizu.SimplePool.Worker.State.t) :: {:ok, Noizu.SimplePool.Worker.State.t}
  @callback shutdown(Noizu.SimplePool.Worker.State.t, context :: any, options :: any, from :: any) :: {:ok | :wait, Noizu.SimplePool.Worker.State.t}
  @callback worker_refs(any, any, any) :: any | nil

  @callback supervisor_hint(ref :: any) :: integer

  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList

  @required_methods ([:call_forwarding, :load])
  @provided_methods ([:call_forwarding_catchall, :fetch, :shutdown, :terminate_hook, :get_direct_link!, :worker_refs, :ping!, :kill!, :crash!, :health_check!, :migrate_shutdown, :on_migrate, :transfer, :save!, :reload!, :supervisor_hint])

  @methods (@required_methods ++ @provided_methods)
  @features ([:auto_identifier, :lazy_load, :inactivitiy_check, :s_redirect])
  @default_features ([:lazy_load, :s_redirect, :inactivity_check])

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        pool: %OptionValue{option: :pool, required: true},
        features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @provided_methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
      }
    }
    initial = OptionSettings.expand(settings, options)
    modifications = Map.put(initial.effective_options, :required, List.foldl(@methods, %{}, fn(x, acc) -> Map.put(acc, x, initial.effective_options.only[x] && !initial.effective_options.override[x]) end))
    %OptionSettings{initial| effective_options: Map.merge(initial.effective_options, modifications)}
  end

  def default_terminate_hook(server, reason, state) do
    case reason do
      {:shutdown, {:migrate, _ref, _, :to, _}} ->
        server.worker_management().unregister!(state.worker_ref, Noizu.ElixirCore.CallingContext.system(%{}))
        #PRI-0 - disabled until rate limit available - server.worker_management().record_event!(state.worker_ref, :migrate, reason, Noizu.ElixirCore.CallingContext.system(%{}), %{})
        reason
      {:shutdown, :migrate} ->
        server.worker_management().unregister!(state.worker_ref, Noizu.ElixirCore.CallingContext.system(%{}))
        #PRI-0 - disabled until rate limit available - server.worker_management().record_event!(state.worker_ref, :migrate, reason, Noizu.ElixirCore.CallingContext.system(%{}), %{})
        reason
      {:shutdown, _details} ->
        server.worker_management().unregister!(state.worker_ref, Noizu.ElixirCore.CallingContext.system(%{}))
        #PRI-0 - disabled until rate limit available - server.worker_management().record_event!(state.worker_ref, :shutdown, reason, Noizu.ElixirCore.CallingContext.system(%{}), %{})
        reason
      _ ->
        server.worker_management().unregister!(state.worker_ref, Noizu.ElixirCore.CallingContext.system(%{}))
        #PRI-0 - disabled until rate limit available - server.worker_management().record_event!(state.worker_ref, :terminate, reason, Noizu.ElixirCore.CallingContext.system(%{}), %{})
        reason
    end
    :ok
  end

  defmacro __using__(options) do
    option_settings = prepare_options(options)
    options = option_settings.effective_options
    required = options.required
    pool = options.pool
    message_processing_provider = Noizu.SimplePool.V2.MessageProcessingBehaviour.DefaultProvider
    quote do
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.V2.InnerStateBehaviour
      @base (unquote(Macro.expand(pool, __CALLER__)))
      @worker (Module.concat([@base, "Worker"]))
      @worker_supervisor (Module.concat([@base, "WorkerSupervisor"]))
      @server (Module.concat([@base, "Server"]))
      @pool_supervisor (Module.concat([@base, "PoolSupervisor"]))
      @simple_pool_group ({@base, @worker, @worker_supervisor, @server, @pool_supervisor})

      use unquote(message_processing_provider), unquote(option_settings)

      alias Noizu.SimplePool.Worker.Link

      #---------------------------------
      #
      #---------------------------------
      def supervisor_hint(ref) do
        case id(ref) do
          v when is_integer(v) -> v
          {a, v} when is_atom(a) and is_integer(v) -> v # To allow for a common id pattern in a number of noizu related projects.
        end
      end

      #---------------------------------
      #
      #---------------------------------
      def get_direct_link!(ref, context), do: @server.router().get_direct_link!(ref, context)


      #-------------------------------------------------------------------------------
      # Outer Context - Exceptions
      #-------------------------------------------------------------------------------
      def reload!(%Noizu.SimplePool.Worker.State{} = state, context, options) do
        case load(state.worker_ref, context, options) do
          nil -> {:reply, :error, state}
          inner_state ->
            {:reply, :ok, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
        end
      end

      #---------------------------------
      #
      #---------------------------------
      def save!(outer_state, _context, _options) do
        Logger.warn("#{__MODULE__}.save method not implemented.")
        {:reply, {:error, :implementation_required}, outer_state}
      end

      #-------------------------------------------------------------------------------
      # Message Handlers
      #-------------------------------------------------------------------------------

      #-----------------------------
      # fetch!/4,5
      #-----------------------------
      def fetch!(state, args, from, context), do: fetch!(state, args, from, context, nil)
      def fetch!(state, _args, _from, _context, _options), do: {:reply, state, state}

      #---------------------------------
      #
      #---------------------------------
      def wake!(%__MODULE__{} = this, command, from, context), do: wake!(this, command, from, context, nil)
      def wake!(%__MODULE__{} = this, _command, _from, _context, _options), do: {:reply, this, this}

      #----------------------------------
      # routing
      #----------------------------------

      #------------------------------------------------------------------------
      # Infrastructure provided call router
      #------------------------------------------------------------------------

      #---------------------------------
      #
      #---------------------------------
      def call_router_internal__default({:passive, envelope}, from, state), do: call_router_internal__default(envelope, from, state)
      def call_router_internal__default({:spawn, envelope}, from, state), do: call_router_internal__default(envelope, from, state)
      def call_router_internal__default(envelope, from, state) do
        case envelope do
          # fetch!
          {:s, {:fetch!, args}, context} -> fetch!(state, args, from, context)
          {:s, {:fetch!, args, opts}, context} -> fetch!(state, args, from, context, opts)

          # wake!
          {:s, {:wake!, args}, context} -> wake!(state, args, from, context)
          {:s, {:wake!, args, opts}, context} -> wake!(state, args, from, context, opts)

          _ -> nil
        end
      end

      #---------------------------------
      #
      #---------------------------------
      def call_router_internal(envelope, from, state), do: call_router_internal__default(envelope, from, state)


      #----------------------------
      #
      #----------------------------
      def cast_router_internal__default(envelope, state) do
        r = call_router_internal(envelope, :cast, state)
        r && as_cast(r)
      end

      #----------------------------
      #
      #----------------------------
      def cast_router_internal(envelope, state), do: cast_router_internal__default(envelope, state)

      #----------------------------
      #
      #----------------------------
      def info_router_internal__default(envelope, state) do
        nil
      end
      #----------------------------
      #
      #----------------------------
      def info_router_internal(envelope, state), do: info_router_internal__default(envelope, state)

      #----------------------------------
      #
      #----------------------------------
      def shutdown(%Noizu.SimplePool.Worker.State{} = state, _context \\ nil, options \\ nil, _from \\ nil), do: {:ok, state}

      #---------------------------------
      #
      #---------------------------------
      def migrate_shutdown(%Noizu.SimplePool.Worker.State{} = state, _context \\ nil), do: {:ok, state}

      #---------------------------------
      #
      #---------------------------------
      def on_migrate(_rebase, %Noizu.SimplePool.Worker.State{} = state, _context \\ nil, _options \\ nil), do: {:ok, state}

      #---------------------------------
      #
      #---------------------------------
      def terminate_hook(reason, state), do: default_terminate_hook(@server, reason, state)

      #---------------------------------
      #
      #---------------------------------
      def worker_refs(_context, _options, _state), do: nil

      #---------------------------------
      #
      #---------------------------------
      def transfer(ref, transfer_state, _context \\ nil), do: {true, transfer_state}






      defoverridable [
        supervisor_hint: 1,
        get_direct_link!: 2,
        reload!: 3,
        save!: 3,
        fetch!: 4,
        fetch!: 5,
        wake!: 4,
        wake!: 5,

        call_router_internal__default: 3,
        call_router_internal: 3,
        cast_router_internal__default: 2,
        cast_router_internal: 2,
        info_router_internal__default: 2,
        info_router_internal: 2,

        shutdown: 1,
        shutdown: 2,
        shutdown: 3,
        shutdown: 4,

        migrate_shutdown: 1,
        migrate_shutdown: 2,

        on_migrate: 2,
        on_migrate: 3,
        on_migrate: 4,

        terminate_hook: 2,
        worker_refs: 3,
        transfer: 2,
        transfer: 3,
      ]

    end # end quote
  end #end defmacro __using__(options)

end # end module
