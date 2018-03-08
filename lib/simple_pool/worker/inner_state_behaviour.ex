#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.InnerStateBehaviour do
  require Logger
  @callback call_forwarding(call :: any, context :: any, state :: any, outer_state :: any) :: {:noreply, state :: any}
  #@callback call_forwarding(call :: any, context :: any, from :: any,  state :: any, outer_state :: any) :: {atom, reply :: any, state :: any}
  @callback fetch(this :: any, options :: any, context :: any) :: {:reply, this :: any, this :: any}

  @callback load(ref :: any) ::  any
  @callback load(ref :: any, context :: any) :: any
  @callback load(ref :: any, context :: any, options :: any) :: any

  @callback terminate_hook(reason :: any,  Noizu.SimplePool.Worker.State.t) :: {:ok, Noizu.SimplePool.Worker.State.t}
  @callback shutdown(Noizu.SimplePool.Worker.State.t, context :: any, options :: any, from :: any) :: {:ok | :wait, Noizu.SimplePool.Worker.State.t}
  @callback worker_refs(any, any, any) :: any | nil

  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList

  @required_methods ([:call_forwarding, :load])
  @provided_methods ([:call_forwarding_catchall, :fetch, :shutdown, :terminate_hook, :get_direct_link!, :worker_refs, :ping!, :kill!, :crash!, :health_check!, :migrate_shutdown, :on_migrate, :transfer, :save!, :reload!])

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
        server.worker_lookup_handler().unregister!(state.worker_ref, Noizu.ElixirCore.CallingContext.system(%{}))
        #PRI-0 - disabled until rate limit available - server.worker_lookup_handler().record_event!(state.worker_ref, :migrate, reason, Noizu.ElixirCore.CallingContext.system(%{}), %{})
        reason
      {:shutdown, :migrate} ->
        server.worker_lookup_handler().unregister!(state.worker_ref, Noizu.ElixirCore.CallingContext.system(%{}))
        #PRI-0 - disabled until rate limit available - server.worker_lookup_handler().record_event!(state.worker_ref, :migrate, reason, Noizu.ElixirCore.CallingContext.system(%{}), %{})
        reason
      {:shutdown, _details} ->
        server.worker_lookup_handler().unregister!(state.worker_ref, Noizu.ElixirCore.CallingContext.system(%{}))
        #PRI-0 - disabled until rate limit available - server.worker_lookup_handler().record_event!(state.worker_ref, :shutdown, reason, Noizu.ElixirCore.CallingContext.system(%{}), %{})
        reason
      _ ->
        server.worker_lookup_handler().unregister!(state.worker_ref, Noizu.ElixirCore.CallingContext.system(%{}))
        #PRI-0 - disabled until rate limit available - server.worker_lookup_handler().record_event!(state.worker_ref, :terminate, reason, Noizu.ElixirCore.CallingContext.system(%{}), %{})
        reason
    end
  end

  def as_cast({:reply, _reply, state}), do: {:noreply, state}
  def as_cast({:noreply, state}), do: {:noreply, state}
  def as_cast({:stop, reason, _reply, state}), do: {:stop, reason, state}
  def as_cast({:stop, reason, state}), do: {:stop, reason, state}

  defmacro __using__(options) do
    option_settings = prepare_options(options)
    options = option_settings.effective_options
    required = options.required
    #features = MapSet.new(options.features)
    pool = options.pool

    quote do
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.InnerStateBehaviour
      @base (unquote(Macro.expand(pool, __CALLER__)))
      @worker (Module.concat([@base, "Worker"]))
      @worker_supervisor (Module.concat([@base, "WorkerSupervisor"]))
      @server (Module.concat([@base, "Server"]))
      @pool_supervisor (Module.concat([@base, "PoolSupervisor"]))
      @simple_pool_group ({@base, @worker, @worker_supervisor, @server, @pool_supervisor})

      alias Noizu.SimplePool.Worker.Link

      if (unquote(required.get_direct_link!)) do
        def get_direct_link!(ref, context), do: @server.get_direct_link!(ref, context)
      end

      if (unquote(required.fetch)) do
        def fetch(%__MODULE__{} = this, _fetch_options, _context), do: {:reply, this, this}
      end

      if (unquote(required.ping!)) do
        def ping!(%__MODULE__{} = this, context), do: {:reply, :pong, this}
      end

      if (unquote(required.reload!)) do
        def reload!(%Noizu.SimplePool.Worker.State{} = state, context, options) do
          case load(state.worker_ref, context, options) do
            nil -> {:reply, :error, state}
            inner_state ->
              {:reply, :ok, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
          end
        end
      end

      if (unquote(required.kill!)) do
        def kill!(%__MODULE__{} = this, context), do: {:stop, {:user_requested, context}, this}
      end

      if (unquote(required.crash!)) do
        def crash!(%__MODULE__{} = this, context, options) do
           raise "#{__MODULE__} - Crash Forced: #{inspect context}, #{inspect options}"
        end
      end

      if (unquote(required.save!)) do
        def save!(outer_state, _context, _options) do
          Logger.warn("#{__MODULE__}.save method not implemented.")
          {:reply, {:error, :implementation_required}, outer_state}
        end
      end

      if (unquote(required.health_check!)) do
        def health_check!(%__MODULE__{} = this, context, options) do
          #TODO accept a health check strategy option
          ref = Noizu.ERP.ref(this)
          events = @server.worker_lookup_handler().events!(ref, context, options) || []
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
      end

      if (unquote(required.call_forwarding_catchall)) do

        # Default Call Forwarding Catch All
        # @Deprecated
        def call_forwarding_catchall(call, context, _from, %__MODULE__{} = this) do
          if context do
            Logger.warn("[#{context.token}] #{__MODULE__} Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
          else
            Logger.warn("[NO_TOKEN] #{__MODULE__} Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
          end
          {:reply, :unsupported_call, this}
        end

        def call_forwarding_catchall(call, context, %__MODULE__{} = this) do
          if context do
            Logger.warn("[#{context.token}] #{__MODULE__} Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
          else
            Logger.warn("[NO_TOKEN] #{__MODULE__} Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
          end
          {:noreply, this}
        end
      end

      if (unquote(required.shutdown)) do
        def shutdown(%Noizu.SimplePool.Worker.State{} = state, _context \\ nil, options \\ nil, _from \\ nil), do: {:ok, state}
      end

      if (unquote(required.migrate_shutdown)) do
        def migrate_shutdown(%Noizu.SimplePool.Worker.State{} = state, _context \\ nil), do: {:ok, state}
      end

      if (unquote(required.on_migrate)) do
        def on_migrate(_rebase, %Noizu.SimplePool.Worker.State{} = state, _context \\ nil, _options \\ nil), do: {:ok, state}
      end

      if (unquote(required.terminate_hook)) do
        def terminate_hook(reason, state), do: default_terminate_hook(@server, reason, state)
      end

      if (unquote(required.worker_refs)) do
        def worker_refs(_context, _options, _state), do: nil
      end

      if (unquote(required.transfer)) do
        def transfer(ref, transfer_state, _context \\ nil), do: {true, transfer_state}
      end

      @before_compile unquote(__MODULE__)
    end # end quote
  end #end defmacro __using__(options)

  defmacro __before_compile__(_env) do
    quote do
      #-----------------------------------------------------------------------------
      # call_forwarding - call
      #-----------------------------------------------------------------------------

      def call_forwarding({:load, options}, context, _from, %__MODULE__{} = this) do
        {:reply, :loaded, load(this, context, options)}
      end
      def call_forwarding(:ping!, context, _from, %__MODULE__{} = this), do: ping!(this, context)
      def call_forwarding({:health_check!, options}, context, _from, %__MODULE__{} = this), do: health_check!(this, context, options)
      def call_forwarding({:fetch, fetch_options}, context, _from, %__MODULE__{} = this), do: fetch(this, fetch_options,  context)
      def call_forwarding(call, context, _from, %__MODULE__{} = this) do
        if context do
          Logger.warn("[#{context.token}] Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
        else
          Logger.warn("[NO_TOKEN] Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
        end
        {:reply, :unsupported_call, this}
      end
      #-----------------------------------------------------------------------------
      # call_forwarding - cast|info
      #-----------------------------------------------------------------------------
      def call_forwarding({:load, options}, context, %__MODULE__{} = this) do
        {:noreply, load(this, context, options)}
      end
      def call_forwarding(:kill!, context, %__MODULE__{} = this), do: kill!(this, context)
      def call_forwarding({:crash!, options}, context, %__MODULE__{} = this), do: crash!(this, context, options)
      def call_forwarding(call, context, %__MODULE__{} = this) do
        if context do
          Logger.warn("[#{context.token}] Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
        else
          Logger.warn("[NO_TOKEN] Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
        end
        {:noreply, this}
      end
    end # end quote
  end # end defmacro __before_compile__(_env)
end # end module
