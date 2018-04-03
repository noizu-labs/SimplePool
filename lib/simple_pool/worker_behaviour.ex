#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.WorkerBehaviour do
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList
  require Logger

  @methods ([:verbose, :options, :option_settings, :start_link, :terminate, :init, :schedule_migrate_shutdown, :clear_migrate_shutdown, :schedule_inactivity_check, :clear_inactivity_check, :save!, :fetch, :reload!, :delayed_init])
  @features ([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])
  @default_features ([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])

  @default_check_interval_ms (1000 * 60 * 5)
  @default_kill_interval_ms (1000 * 60 * 15)

  @callback option_settings() :: Noizu.SimplePool.OptionSettings.t

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: :auto},
        worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
        check_interval_ms: %OptionValue{option: :check_interval_ms, default: Application.get_env(:noizu_simple_pool, :default_inactivity_check_interval_ms, @default_check_interval_ms)},
        kill_interval_ms: %OptionValue{option: :kill_interval_ms, default: Application.get_env(:noizu_simple_pool, :default_inactivity_kill_interval_ms, @default_kill_interval_ms)},
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
    features = MapSet.new(options.features)
    verbose = options.verbose

    quote do
      import unquote(__MODULE__)
      require Logger
      @behaviour Noizu.SimplePool.WorkerBehaviour
      use GenServer
      @base (Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat)
      @server (Module.concat([@base, "Server"]))
      @worker_state_entity (Noizu.SimplePool.Behaviour.expand_worker_state_entity(@base, unquote(options.worker_state_entity)))
      @check_interval_ms (unquote(options.check_interval_ms))
      @kill_interval_s (unquote(options.kill_interval_ms)/1000)
      @migrate_shutdown_interval_ms (5_000)
      @migrate_shutdown unquote(MapSet.member?(features, :migrate_shutdown))
      @inactivity_check unquote(MapSet.member?(features, :inactivity_check))
      @lazy_load unquote(MapSet.member?(features, :lazy_load))
      @base_verbose (unquote(verbose))


      @option_settings unquote(Macro.escape(option_settings))
      @options unquote(Macro.escape(options))

      if (unquote(required.verbose)) do
        def verbose(), do: Noizu.SimplePool.WorkerBehaviourDefault.verbose(@base_verbose, @base)
      end

      if (unquote(required.option_settings)) do
        def option_settings(), do: @option_settings
      end

      if (unquote(required.options)) do
        def options(), do: @options
      end

      # @start_link
      if (unquote(required.start_link)) do
        def start_link(ref, context) do
          if (verbose()) do
            Logger.info(fn -> @base.banner("START_LINK/1 #{__MODULE__} (#{inspect ref})") end)
          end
          GenServer.start_link(__MODULE__, {ref, context})
        end

        def start_link(ref, args, context) do
          if (verbose()) do
            Logger.info(fn -> @base.banner("START_LINK/2.migrate #{__MODULE__} (#{inspect args})") end)
          end
          GenServer.start_link(__MODULE__, {:migrate, ref, args, context})
        end
      end # end start_link

      # @terminate
      if (unquote(required.terminate)) do
        def terminate(reason, state) do
          if (verbose()) do
            Logger.info(fn -> @base.banner("TERMINATE #{__MODULE__} (#{inspect state.worker_ref}\n Reason: #{inspect reason}") end)
          end
          @worker_state_entity.terminate_hook(reason, Noizu.SimplePool.WorkerBehaviourDefault.clear_inactivity_check(state))
          #@server.worker_lookup_handler().record_event!(state.worker_ref, :terminate, reason, Noizu.ElixirCore.CallingContext.system(%{}), %{})
        end
      end # end start_link

      @doc """
      @init
      @TODO use defmacro to strip out unnecessary compile time conditionals
      """
      if (unquote(required.init)) do
        def init(arg) do
          Noizu.SimplePool.WorkerBehaviourDefault.init({__MODULE__, @server, @base, @worker_state_entity, @inactivity_check, @lazy_load}, arg)
        end
      end # end init

      # @s_redirect
      if unquote(MapSet.member?(features, :s_redirect)) || unquote(MapSet.member?(features, :s_redirect_handle)) do
        def handle_call({_type, {@server, _ref, _timeout}, call}, from, state), do: handle_call(call, from, state)
        def handle_cast({_type, {@server, _ref}, call}, state), do: handle_cast(call, state)
        def handle_info({_type, {@server, _ref}, call}, state), do: handle_info(call, state)

        def handle_cast({:s_cast, {call_server, ref}, {:s, _inner, context} = call}, state) do
          Logger.info(fn -> "Dispatch Error: #{inspect call} ->  #{__MODULE__} #{inspect state}" end)
          {:noreply, state}
        end # end handle_cast/:s_cast

        def handle_cast({:s_cast!, {call_server, ref}, {:s, _inner, context} = call}, state) do
          Logger.info(fn -> "Dispatch Error: #{inspect call} ->  #{__MODULE__} #{inspect state}" end)
          {:noreply, state}
        end # end handle_cast/:s_cast!

        def handle_call({:s_call, {call_server, ref, timeout}, {:s, _inner, context} = call}, from, state) do
          Logger.info(fn -> "Dispatch Error: #{inspect call} ->  #{__MODULE__} #{inspect state}" end)
          {:reply, :s_retry, state}
        end # end handle_call/:s_call

        def handle_call({:s_call!, {call_server, ref, timeout}, {:s, _inner, context}} = call, from, state) do
          Logger.info(fn -> "Dispatch Error: #{inspect call} ->  #{__MODULE__} #{inspect state}" end)
          {:reply, :s_retry, state}
        end # end handle_call/:s_call!
      end # if feature.s_redirect

      def handle_call({_a, _b, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: :delayed_init} = state) do
         state = delayed_init(state, context)
         handle_call(call, from, state)
      end

      def handle_cast({_a, _b, context} = call, %Noizu.SimplePool.Worker.State{initialized: :delayed_init} = state) do
        state = delayed_init(state, context)
        handle_cast(call, state)
      end

      def handle_info({_a, _b, context} = call, %Noizu.SimplePool.Worker.State{initialized: :delayed_init} = state) do
        state = delayed_init(state, context)
        handle_info(call, state)
      end

      if (unquote(required.delayed_init)) do
        def delayed_init(state, context) do
          Noizu.SimplePool.WorkerBehaviourDefault.delayed_init({__MODULE__, @server, @base, @worker_state_entity, @inactivity_check, @lazy_load}, state, context)
        end
      end

      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------
      if (unquote(required.schedule_migrate_shutdown)) do
        def schedule_migrate_shutdown(context, state) do
          Noizu.SimplePool.WorkerBehaviourDefault.schedule_migrate_shutdown(@migrate_shutdown_interval_ms, context, state)
        end
      end
      if (unquote(required.clear_migrate_shutdown)) do
        def clear_migrate_shutdown(state) do
          Noizu.SimplePool.WorkerBehaviourDefault.clear_migrate_shutdown(state)
        end
      end
      def handle_info({:i, {:migrate_shutdown, ref}, context} = call, %Noizu.SimplePool.Worker.State{migrating: status} = state) do
        Noizu.SimplePool.WorkerBehaviourDefault.handle_migrate_shutdown(__MODULE__, @server, @worker_state_entity, @inactivity_check, call, state)
      end # end handle_info/:activity_check

      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------

      if (unquote(required.schedule_inactivity_check)) do
        def schedule_inactivity_check(context, state) do
          Noizu.SimplePool.WorkerBehaviourDefault.schedule_inactivity_check(@check_interval_ms, context, state)
        end
      end
      if (unquote(required.clear_inactivity_check)) do
        def clear_inactivity_check(state) do
          Noizu.SimplePool.WorkerBehaviourDefault.clear_inactivity_check(state)
        end
      end

      def handle_info({:i, {:activity_check, ref}, context} = call, %Noizu.SimplePool.Worker.State{initialized: _i} = state) do
        Noizu.SimplePool.WorkerBehaviourDefault.handle_activity_check(__MODULE__, @server, @worker_state_entity, @kill_interval_s, call, state)
      end # end handle_info/:activity_check

      #-------------------------------------------------------------------------
      # Special Section for handlers that require full context
      # @TODO change call_Forwarding to allow passing back and forth full state.
      #-------------------------------------------------------------------------
      if (unquote(required.save!)) do
        def handle_call({:s, {:save!, options}, context} = call, _from, %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.save!(state, options, context)
        end

        def handle_cast({:s, {:save!, options}, context} = call, %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.save!(state, options, context) |> Noizu.SimplePool.InnerStateBehaviour.as_cast()
        end

        def handle_info({:s, {:save!, options}, context} = call, %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.save!(state, options, context) |> Noizu.SimplePool.InnerStateBehaviour.as_cast()
        end
      end

      if (unquote(required.fetch)) do
        def handle_call({:s, {:fetch, :state}, context} = call, _from,  %Noizu.SimplePool.Worker.State{} = state) do
          {:reply, state, state}
        end

        def handle_call({:s, {:fetch, :process}, context} = call, _from,  %Noizu.SimplePool.Worker.State{} = state) do
          {:reply, {@worker_state_entity.ref(state.inner_state), self(), node()}, state}
        end
      end

      if (unquote(required.reload!)) do
        def handle_call({:s, {:reload!, options}, context} = call, _from,  %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.reload!(state, options, context)
        end

        def handle_cast({:s, {:reload!, options}, context} = call, %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.reload!(state, options, context) |> Noizu.SimplePool.InnerStateBehaviour.as_cast()
        end

        def handle_info({:s, {:reload!, options}, context} = call, %Noizu.SimplePool.Worker.State{} = state) do
          @worker_state_entity.reload!(state, options, context) |> Noizu.SimplePool.InnerStateBehaviour.as_cast()
        end
      end

      #-------------------------------------------------------------------------
      # Load handler, placed before lazy load to avoid resending load commands
      #-------------------------------------------------------------------------
      def handle_cast({:s, {:load, options}, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
        Noizu.SimplePool.WorkerBehaviourDefault.handle_cast_load(@worker_state_entity, @inactivity_check, call, state)
      end

      def handle_info({:s, {:load, options}, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
        handle_cast({:s, {:load, options}, context}, state)
      end

      def handle_call({:s, {:load, options}, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
        Noizu.SimplePool.WorkerBehaviourDefault.handle_call_load(@worker_state_entity, @inactivity_check, call, from, state)
      end

      def handle_cast({:s, {:migrate!, ref, rebase, options}, context} = call, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
        Noizu.SimplePool.WorkerBehaviourDefault.handle_cast_migrate(__MODULE__, @server, @worker_state_entity, @migrate_shutdown, call, state)
      end

      def handle_info({:s, {:migrate!, ref, rebase, options}, context}, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
        handle_cast({:s, {:migrate!, ref, rebase, options}, context}, state)
      end

      def handle_call({:s, {:migrate!, ref, rebase, options}, context}  = call, from, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
        Noizu.SimplePool.WorkerBehaviourDefault.handle_call_migrate(__MODULE__, @server, @worker_state_entity, @migrate_shutdown, call, from, state)
      end

      #-------------------------------------------------------------------------
      # Lazy Load Handling Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :lazy_load)) do
        def handle_call({:s, _inner, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          Noizu.SimplePool.WorkerBehaviourDefault.handle_call_lazy_load(__MODULE__, @worker_state_entity, call, from, state)
        end # end handle_call

        def handle_cast({:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          Noizu.SimplePool.WorkerBehaviourDefault.handle_cast_lazy_load(__MODULE__, @worker_state_entity, call, state)
        end # end handle_cast

        def handle_info({:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          Noizu.SimplePool.WorkerBehaviourDefault.handle_info_lazy_load(__MODULE__, @worker_state_entity, call, state)
        end # end handle_info
      end # end lazy_load feature block

      # Capture shutdown with full state  to allow for timer clearing, etc.
      def handle_call({:s, {:shutdown, options} = _inner_call, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: _inner_state} = state) do
        Noizu.SimplePool.WorkerBehaviourDefault.handle_call_shutdown(__MODULE__, @worker_state_entity, call, from, state)
      end

      #-------------------------------------------------------------------------
      # Call Forwarding Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :call_forwarding)) do
        def handle_info({:s, inner_call, context} = call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          Noizu.SimplePool.WorkerBehaviourDefault.handle_cast_forwarding(@worker_state_entity, @inactivity_check, call, state)
        end

        def handle_cast({:s, inner_call, context} = call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          Noizu.SimplePool.WorkerBehaviourDefault.handle_cast_forwarding(@worker_state_entity, @inactivity_check, call, state)
        end

        def handle_call({:s, inner_call, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          Noizu.SimplePool.WorkerBehaviourDefault.handle_call_forwarding(@worker_state_entity, @inactivity_check, call, from, state)
        end
      end # end call forwarding feature section
      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
      def handle_call(uncaught, _from, state) do
        Logger.info(fn -> "Uncaught handle_call to #{__MODULE__} . . . #{inspect uncaught}"  end)
        {:noreply, state}
      end

      def handle_cast(uncaught, state) do
        Logger.info(fn -> "Uncaught handle_cast to #{__MODULE__} . . . #{inspect uncaught}"  end)
        {:noreply, state}
      end

      def handle_info(uncaught, state) do
        Logger.info(fn -> "Uncaught handle_info to #{__MODULE__} . . . #{inspect uncaught}"  end)
        {:noreply, state}
      end
    end # end quote
  end # end __before_compile__
end
