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

  def as_cast({:reply, _reply, state}), do: {:noreply, state}
  def as_cast({:noreply, state}), do: {:noreply, state}
  def as_cast({:stop, reason, _reply, state}), do: {:stop, reason, state}
  def as_cast({:stop, reason, state}), do: {:stop, reason, state}

  defmacro __using__(options) do
    option_settings = prepare_options(options)
    options = option_settings.effective_options
    required = options.required
    pool = options.pool

    quote do
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.V2.InnerStateBehaviour
      @base (unquote(Macro.expand(pool, __CALLER__)))
      @worker (Module.concat([@base, "Worker"]))
      @worker_supervisor (Module.concat([@base, "WorkerSupervisor"]))
      @server (Module.concat([@base, "Server"]))
      @pool_supervisor (Module.concat([@base, "PoolSupervisor"]))
      @simple_pool_group ({@base, @worker, @worker_supervisor, @server, @pool_supervisor})


      use Noizu.SimplePool.V2.MessageProcessingBehaviour.DefaultProvider

      alias Noizu.SimplePool.Worker.Link

        def supervisor_hint(ref) do
          case id(ref) do
            v when is_integer(v) -> v
            {a, v} when is_atom(a) and is_integer(v) -> v # To allow for a common id pattern in a number of noizu related projects.
          end
        end


        def get_direct_link!(ref, context), do: @server.router().get_direct_link!(ref, context)

        def fetch(%__MODULE__{} = this, _fetch_options, _context), do: {:reply, this, this}

        def ping!(%__MODULE__{} = this, context), do: {:reply, :pong, this}

        def reload!(%Noizu.SimplePool.Worker.State{} = state, context, options) do
          case load(state.worker_ref, context, options) do
            nil -> {:reply, :error, state}
            inner_state ->
              {:reply, :ok, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
          end
        end

        def kill!(%__MODULE__{} = this, context), do: {:stop, {:user_requested, context}, this}

        def crash!(%__MODULE__{} = this, context, options) do
           throw "#{__MODULE__} - Crash Forced: #{inspect context}, #{inspect options}"
        end

        def save!(outer_state, _context, _options) do
          Logger.warn("#{__MODULE__}.save method not implemented.")
          {:reply, {:error, :implementation_required}, outer_state}
        end

        def health_check!(%__MODULE__{} = this, context, options) do
          #TODO accept a health check strategy option
          ref = Noizu.ERP.ref(this)
          events = @server.worker_management().events!(ref, context, options) || []
          cut_off = :os.system_time(:seconds) - (60*60*15)
          accum = events
                  |> Enum.filter(fn(x) -> x.time > cut_off end)
                  |> Enum.reduce(%{}, fn(x, acc) -> update_in(acc, [x.event], &( (&1 || 0) + 1)) end)
          weights = %{exit: 0.5,  start: 0.75,  terminate: 1.00,  timeout: 0.25}
          check = Enum.reduce(weights, 0, fn({k,w}, acc) -> acc + ((accum[k] || 0) * w) end)
          status = cond do
            check < 5 -> :online
            check < 8 -> :degraded
            true -> :critical
          end
          {:reply, %Noizu.SimplePool.Worker.HealthCheck{identifier: ref, status: status, event_frequency: accum, check: check, events: events}, this}
        end

        def shutdown(%Noizu.SimplePool.Worker.State{} = state, _context \\ nil, options \\ nil, _from \\ nil), do: {:ok, state}
        def migrate_shutdown(%Noizu.SimplePool.Worker.State{} = state, _context \\ nil), do: {:ok, state}
        def on_migrate(_rebase, %Noizu.SimplePool.Worker.State{} = state, _context \\ nil, _options \\ nil), do: {:ok, state}
        def terminate_hook(reason, state), do: default_terminate_hook(@server, reason, state)
        def worker_refs(_context, _options, _state), do: nil
        def transfer(ref, transfer_state, _context \\ nil), do: {true, transfer_state}


      defoverridable [
        supervisor_hint: 1,
        get_direct_link!: 2,
        fetch: 3,
        ping!: 2,
        reload!: 3,
        kill!: 2,
        crash!: 3,
        save!: 3,
        health_check!: 3,
        shutdown: 4,
        migrate_shutdown: 2,
        on_migrate: 4,
        terminate_hook: 2,
        worker_refs: 3,
        transfer: 3
      ]

    end # end quote
  end #end defmacro __using__(options)

end # end module
