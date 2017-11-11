defmodule Noizu.SimplePool.WorkerBehaviour do
  alias Noizu.SimplePool.OptionSettings
  alias Noizu.SimplePool.OptionValue
  alias Noizu.SimplePool.OptionList
  require Logger
  @methods([:start_link, :init, :terminate, :fetch, :save!])
  @features([:auto_identifier, :lazy_load, :async_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])
  @default_features([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check, :call_forwarding, :graceful_stop, :crash_protection, :migrate_shutdown])

  @default_check_interval_ms(1000 * 60 * 5)
  @default_kill_interval_ms(1000 * 60 * 15)

  @callback option_settings() :: Noizu.SimplePool.OptionSettings.t

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        features: %OptionList{option: :features, default: Application.get_env(:noizu_simple_pool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: Application.get_env(:noizu_simple_pool, :verbose, false)},
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
      @base(Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat)
      @server(Module.concat([@base, "Server"]))
      @worker_state_entity(Noizu.SimplePool.Behaviour.expand_worker_state_entity(@base, unquote(options.worker_state_entity)))
      @check_interval_ms(unquote(options.check_interval_ms))
      @kill_interval_s(unquote(options.kill_interval_ms)/1000)
      @migrate_shutdown_interval_ms(5_000)

      def option_settings do
        unquote(Macro.escape(option_settings))
      end

      # @start_link
      if (unquote(required.start_link)) do
        def start_link(args) do
          if (unquote(verbose)) do
            @base.banner("START_LINK/1 #{__MODULE__} (#{inspect args})") |> Logger.info()
          end
          GenServer.start_link(__MODULE__, args)
        end

        def start_link(ref, args) do
          if (unquote(verbose)) do
            @base.banner("START_LINK/2.migrate #{__MODULE__} (#{inspect args})") |> Logger.info()
          end
          GenServer.start_link(__MODULE__, {:migrate, ref, args})
        end

        def start_link(a,b,c) do
          Logger.error "start_link/3? #{inspect {a, b, c}}"
        end
      end # end start_link

      # @terminate
      if (unquote(required.terminate)) do
        def terminate(reason, state) do
          if (unquote(verbose)) do
            @base.banner("TERMINATE #{__MODULE__} (#{inspect state.worker_ref}\n Reason: #{inspect reason}") |> Logger.info()
          end
          @worker_state_entity.terminate_hook(reason, clear_inactivity_check(state))
        end
      end # end start_link

      @doc """
      @init
      @TODO use defmacro to strip out unnecessary compile time conditionals
      """
      if (unquote(required.init)) do


        def init({:migrate, ref, {:transfer, initial_state}}) do
          if (unquote(verbose)) do
            @base.banner("INIT/1.transfer #{__MODULE__} (#{inspect ref }") |> Logger.info()
          end
          @server.worker_register!(ref, {self(), node()})

          {initialized, inner_state} = @worker_state_entity.transfer(ref, initial_state.inner_state)

          if unquote(MapSet.member?(features, :inactivity_check)) do
            state2 = %Noizu.SimplePool.Worker.State{initial_state| initialized: initialized, worker_ref: ref, inner_state: inner_state, last_activity: :os.system_time(:seconds)}
            state3 = schedule_inactivity_check(nil, state2)
            {:ok, state3}
          else
            {:ok, %Noizu.SimplePool.Worker.State{initial_state| initialized: initialized, worker_ref: ref, inner_state: inner_state}}
          end
        end

        def init(ref) do
          if (unquote(verbose)) do
            @base.banner("INIT/1 #{__MODULE__} (#{inspect ref }") |> Logger.info()
          end
          @server.worker_register!(ref, {self(), node()})
          {initialized, inner_state} = if unquote(MapSet.member?(features, :lazy_load)) do
            case @worker_state_entity.load(ref) do
              nil -> {false, nil}
              inner_state -> {true, inner_state}
            end
          else
            {false, nil}
          end
          if unquote(MapSet.member?(features, :inactivity_check)) do
            state = %Noizu.SimplePool.Worker.State{initialized: initialized, worker_ref: ref, inner_state: inner_state, last_activity: :os.system_time(:seconds)}
            state = schedule_inactivity_check(nil, state)
            {:ok, state}
          else
            {:ok, %Noizu.SimplePool.Worker.State{initialized: initialized, worker_ref: ref, inner_state: inner_state}}
          end
        end

      end # end init

      # @s_redirect
      if unquote(MapSet.member?(features, :s_redirect)) || unquote(MapSet.member?(features, :s_redirect_handle)) do
        def handle_call({_type, {@server, _ref, _timeout}, call}, from, state), do: handle_call(call, from, state)
        def handle_cast({_type, {@server, _ref}, call}, state), do: handle_cast(call, state)

        def handle_cast({:s_cast, {call_server, ref}, {:s, _inner, context} = call}, state) do
          call_server.worker_clear!(ref, {self(), node()}, context)
          call_server.s_cast(ref, call)
          {:noreply, state}
        end # end handle_cast/:s_cast

        def handle_cast({:s_cast!, {call_server, ref}, {:s, _inner, context} = call}, state) do
          call_server.worker_clear!(ref, {self(), node()}, context)
          call_server.s_cast!(ref, call)
          {:noreply, state}
        end # end handle_cast/:s_cast!

        def handle_call({:s_call, {call_server, ref, timeout}, {:s, _inner, context} = call}, from, state) do
          call_server.worker_clear!(ref, {self(), node()}, context)
          {:reply, :s_retry, state}
        end # end handle_call/:s_call

        def handle_call({:s_call!, {call_server, ref, timeout}, {:s, _inner, context}} = call, from, state) do
          call_server.worker_clear!(ref, {self(), node()}, context)
          {:reply, :s_retry, state}
        end # end handle_call/:s_call!
      end # if feature.s_redirect

      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :migrate_shutdown)) do
        def schedule_migrate_shutdown(context, state) do
          {:ok, mt_ref} = :timer.send_after(@migrate_shutdown_interval_ms, self(), {:i, {:migrate_shutdown, state.worker_ref}, context})
          %Noizu.SimplePool.Worker.State{state| extended: Map.put(state.extended, :mt_ref, mt_ref)}
        end

        def clear_migrate_shutdown(state) do
          case Map.get(state.extended, :mt_ref) do
            nil -> state
            mt_ref ->
              :timer.cancel(mt_ref)
              %Noizu.SimplePool.Worker.State{state| extended: Map.put(state.extended || %{}, :mt_ref, nil)}
          end
        end

        def handle_info({:i, {:migrate_shutdown, ref}, context}, %Noizu.SimplePool.Worker.State{migrating: true} = state) do
          if ref == state.worker_ref do
            state = clear_migrate_shutdown(state)
            state = if unquote(MapSet.member?(features, :inactivity_check)) do
              clear_inactivity_check(state)
            else
              state
            end

            if state.initialized do
              case @worker_state_entity.migrate_shutdown(state, context) do
                {:ok, state} ->
                  @server.worker_terminate!(ref, nil, context)
                  {:noreply, state}
                {:wait, state} ->
                  {:noreply, schedule_migrate_shutdown(context, state)}
              end
            else
              @server.worker_terminate!(ref, nil, context)
              {:noreply, state}
            end
          else
            {:noreply, state}
          end
        end # end handle_info/:activity_check

        def handle_info({:i, {:migrate_shutdown, ref}, context}, %Noizu.SimplePool.Worker.State{migrating: false} = state) do
          Logger.error("#{__MODULE__}.migrate_shutdown called when not in migrating state")
          {:noreply, state}
        end # end handle_info/:activity_check
      end # end activity_check feature section

      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :inactivity_check)) do
        def schedule_inactivity_check(context, state) do
          {:ok, t_ref} = :timer.send_after(@check_interval_ms, self(), {:i, {:activity_check, state.worker_ref}, context})
          %Noizu.SimplePool.Worker.State{state| extended: Map.put(state.extended || %{}, :t_ref, t_ref)}
        end

        def clear_inactivity_check(state) do
          case Map.get(state.extended, :t_ref) do
            nil -> state
            t_ref ->
              :timer.cancel(t_ref)
              %Noizu.SimplePool.Worker.State{state| extended: Map.put(state.extended, :t_ref, nil)}
          end
        end

        def handle_info({:i, {:activity_check, ref}, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          if ref == state.worker_ref do
            if ((state.last_activity == nil) || ((state.last_activity + @kill_interval_s) < :os.system_time(:seconds))) do
              @server.worker_remove!(ref, [force: true], context)
              {:noreply, clear_inactivity_check(state)}
            else
              {:noreply, schedule_inactivity_check(context, state)}
            end
          else
            {:noreply, state}
          end
        end # end handle_info/:activity_check

        def handle_info({:i, {:activity_check, ref}, context}, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
          if ref == state.worker_ref do
            if ((state.last_activity == nil) || ((state.last_activity + @kill_interval_s) < :os.system_time(:seconds))) do
              case @worker_state_entity.shutdown(state, [], context, nil) do
                {:ok, state} ->
                  @server.worker_remove!(state.worker_ref, [force: true], context)
                  {:noreply, state}
                {:wait, state} ->
                  # @TODO force termination conditions needed.
                  {:noreply, schedule_inactivity_check(context, state)}
              end
            else
              {:noreply, schedule_inactivity_check(context, state)}
            end
          else
            {:noreply, state}
          end
        end # end handle_info/:activity_check
      end # end activity_check feature section


      #-------------------------------------------------------------------------
      # Load handler, placed before lazy load to avoid resending load commands
      #-------------------------------------------------------------------------

      def handle_cast({:s, {:load, options}, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
        case @worker_state_entity.load(state.worker_ref, options, context) do
          nil -> {:noreply, state}
          inner_state ->
            if unquote(MapSet.member?(features, :inactivity_check)) do
              {:noreply, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
            else
              {:noreply, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}}
            end
        end
      end

      def handle_call({:s, {:load, options}, context}, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
        case @worker_state_entity.load(state.worker_ref, options, context) do
          nil -> {:reply, :not_found, state}
          inner_state ->
            if unquote(MapSet.member?(features, :inactivity_check)) do
              {:reply, inner_state, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
            else
              {:reply, inner_state, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}}
            end
        end
      end

      def handle_cast({:s, {:migrate!, ref, rebase, options}, context}, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
        cond do
          (rebase == node() && ref == state.worker_ref) -> {:noreply, state}
          Node.ping(rebase) == :pang -> {:noreply, state}
          true ->
            # TODO support for delay/halt hooks.
            {:ok, state} = @worker_state_entity.on_migrate(rebase, state, options, context)
            @server.worker_start_transfer!(ref, rebase, state, options, context)

            state = %Noizu.SimplePool.Worker.State{state| extended: Map.put(state.extended, :migrate_start, DateTime.utc_now()), migrating: true}
            state = if unquote(MapSet.member?(features, :migrate_shutdown)) do
              schedule_migrate_shutdown(context, state)
            else
              spawn fn() ->
                  Process.sleep(500)
                  @server.worker_terminate!(ref, nil, context)
                end
              state
            end
            {:noreply, state}
          end  #end cond do
      end

      def handle_call({:s, {:migrate!, ref, rebase, options}, context}, from, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
        cond do
          (rebase == node() && ref == state.worker_ref) -> {:reply, {:ok, self()}, state}
          Node.ping(rebase) == :pang -> {:reply, {:error, {:pang, rebase}}, state}
          true ->
            # TODO support for delay/halt hooks.
            {:ok, state} = @worker_state_entity.on_migrate(rebase, state, context)
            response = @server.worker_start_transfer!(ref, rebase, state, options, context)
            state = case response do
              {:ok, _p} ->
                state = %Noizu.SimplePool.Worker.State{state| extended: Map.put(state.extended, :migrate_start, DateTime.utc_now()), migrating: true}
                state = if unquote(MapSet.member?(features, :migrate_shutdown)) do
                  schedule_migrate_shutdown(context, state)
                else
                  spawn fn() ->
                      Process.sleep(500)
                      @server.worker_terminate!(ref, nil, context)
                    end
                  state
                end
            end
            {:reply, response, state}
        end
      end

      #-------------------------------------------------------------------------
      # Lazy Load Handling Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :lazy_load)) do
        def handle_call({:s, _inner, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          case @worker_state_entity.load(state.worker_ref, context) do
            nil -> {:reply, :initilization_failed, state}
            inner_state ->
              handle_call(call, from, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
          end
        end # end handle_call

        def handle_cast({:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          case @worker_state_entity.load(state.worker_ref, context) do
            nil -> {:noreply, state}
            inner_state ->
              handle_cast(call, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
          end
        end # end handle_cast

        def handle_info({:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          case @worker_state_entity.load(state.worker_ref, context) do
            nil -> {:noreply, state}
            inner_state ->
              handle_info(call, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
          end
        end # end handle_info
      end # end lazy_load feature block

      # Capture shutdown with full state  to allow for timer clearing, etc.
      def handle_call({:s, {:shutdown, options} = _inner_call, context} = _call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: _inner_state} = state) do
        {reply, state} = @worker_state_entity.shutdown(state, options, context, from)
        case reply do
          :ok ->
            {:reply, reply, clear_inactivity_check(state)}
          :wait ->
            {:reply, reply, state}
        end
      end

      #-------------------------------------------------------------------------
      # Special Section for handlers that require full context
      # @TODO change call_Forwarding to allow passing back and forth full state.
      #-------------------------------------------------------------------------
      if (unquote(required.save!)) do
        def handle_call({:s, {:save!, options}, context} = call, _from,  %Noizu.SimplePool.Worker.State{initialized: true, inner_state: _inner_state} = state) do
          @worker_state_entity.save!(state, options, context)
        end

        def handle_cast({:s, {:save!, options}, context} = call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: _inner_state} = state) do
          @worker_state_entity.save!(state, options, context) |> @worker_state_entity.as_cast()
        end

        def handle_info({:s, {:save!, options}, context} = call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: _inner_state} = state) do
          @worker_state_entity.save!(state, options, context) |> @worker_state_entity.as_cast()
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

      #-------------------------------------------------------------------------
      # Call Forwarding Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :call_forwarding)) do
        def handle_info({:s, inner_call, context} = call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          case @worker_state_entity.call_forwarding(inner_call, context, inner_state) do
            {:stop, reason, inner_state} ->
              if unquote(MapSet.member?(features, :inactivity_check)) do
                {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
              else
                {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
              end
            {reply, inner_state} ->
              if unquote(MapSet.member?(features, :inactivity_check)) do
                {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
              else
                {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
              end
          end
        end

        def handle_cast({:s, inner_call, context} = call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          case @worker_state_entity.call_forwarding(inner_call, context, inner_state) do
            {:stop, reason, inner_state} ->
              if unquote(MapSet.member?(features, :inactivity_check)) do
                {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
              else
                {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
              end
            {reply, inner_state} ->
              if unquote(MapSet.member?(features, :inactivity_check)) do
                {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
              else
                {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
              end
          end
        end

        def handle_call({:s, inner_call, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          case @worker_state_entity.call_forwarding(inner_call, context, from, inner_state) do
            {:stop, reason, response, inner_state} ->
              if unquote(MapSet.member?(features, :inactivity_check)) do
                {:stop, reason, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
              else
                {:stop, reason, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
              end
            {reply, response, inner_state} ->
              if unquote(MapSet.member?(features, :inactivity_check)) do
                {reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
              else
                {reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
              end
          end
        end
      end # end call forwarding feature section
      @before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  defmacro __before_compile__(_env) do
    quote do
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
