defmodule Noizu.SimplePool.WorkerBehaviour do
  alias Noizu.SimplePool.OptionSettings
  alias Noizu.SimplePool.OptionValue
  alias Noizu.SimplePool.OptionList

  @methods([:start_link, :init, :terminate])
  @features([:auto_identifier, :lazy_load, :asynch_load, :inactivity_check, :s_redirect, :s_redirect_handle, :ref_lookup_cache])
  @default_features([:lazy_load, :s_redirect, :s_redirect_handle, :inactivity_check])

  @default_check_interval_ms(1000 * 60 * 2)
  @default_kill_interval_ms(1000 * 60 * 10)

  @callback option_settings() :: Noizu.SimplePool.OptionSettings.t

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        features: %OptionList{option: :features, default: Application.get_env(Noizu.SimplePool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        verbose: %OptionValue{option: :verbose, default: Application.get_env(Noizu.SimplePool, :verbose, false)},
        worker_state_entity: %OptionValue{option: :worker_state_entity, default: :auto},
        check_interval_ms: %OptionValue{option: :check_interval_ms, default: Application.get_env(Noizu.SimplePool, :default_inactivity_check_interval_ms, @default_check_interval_ms)},
        kill_interval_ms: %OptionValue{option: :kill_interval_ms, default: Application.get_env(Noizu.SimplePool, :default_inactivity_kill_interval_ms, @default_kill_interval_ms)},
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
      @base(Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat)
      @server(Module.concat([@base, "Server"]))
      @worker_state_entity(Noizu.SimplePool.Behaviour.expand_worker_state_entity(@base, unquote(options.worker_state_entity)))
      @check_interval_ms(unquote(options.check_interval_ms))
      @kill_interval_s(unquote(options.kill_interval_ms)/1000)

      def option_settings do
        unquote(Macro.escape(option_settings))
      end

      # @start_link
      if (unquote(required.start_link)) do
        def start_link(ref) do
          if (unquote(verbose)) do
            @base.banner("START_LINK #{__MODULE__} (#{inspect ref})") |> Logger.info()
          end
          GenServer.start_link(__MODULE__, ref)
        end
      end # end start_link

      # @terminate
      if (unquote(required.terminate)) do
        def terminate(reason, state) do
          if (unquote(verbose)) do
            @base.banner("TERMINATE #{__MODULE__} (#{inspect state.worker_ref}") |> Logger.info()
          end
          # @TODO perform dereg in server method.
          @server.worker_deregister!(state.worker_ref)
          @worker_state_entity.terminate_hook(reason, state)
        end
      end # end start_link

      @doc """
      @init
      @TODO use defmacro to strip out unnecessary compile time conditionals
      """
      if (unquote(required.init)) do
        def init(ref) do
          if (unquote(verbose)) do
            @base.banner("INIT #{__MODULE__} (#{inspect ref }") |> Logger.info()
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
            :timer.send_after(@check_interval_ms, self(), {:activity_check, ref})
            {:ok, %Noizu.SimplePool.Worker.State{initialized: initialized, worker_ref: ref, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
          else
            {:ok, %Noizu.SimplePool.Worker.State{initialized: initialized, worker_ref: ref, inner_state: inner_state}}
          end
        end
      end # end init

      # @s_redirect
      if unquote(MapSet.member?(features, :s_redirect)) || unquote(MapSet.member?(features, :s_redirect_handle)) do
        def handle_cast({_type, {@server, _ref}, call}, state), do: handle_cast(call, state)
        def handle_call({_type, {@server, _ref}, call}, from, state), do: handle_call(call, from, state)

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
      if unquote(MapSet.member?(features, :inactivity_check)) do
        def handle_info({:i, {:activity_check, ref}, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          if ref == state.worker_ref do
            if ((state.last_activity == nil) || ((state.last_activity + @kill_interval_s) < :os.system_time(:seconds))) do
              @server.worker_remove!(ref, [force: true], context)
            else
              :timer.send_after(@check_interval_ms, self(), {:i, {:activity_check, ref}, context})
            end
            {:noreply, state}
          else
            {:noreply, state}
          end
        end # end handle_info/:activity_check

        def handle_info({:i, {:activity_check, ref}, context}, %Noizu.SimplePool.Worker.State{initialized: true} = state) do
          if ref == state.worker_ref do
            if ((state.last_activity == nil) || ((state.last_activity + @kill_interval_s) < :os.system_time(:seconds))) do
              case @worker_state_entity.shutdown(context, state.inner_state) do
                {:ok, inner_state} ->
                  state = %Noizu.SimplePool.Worker.State{inner_state: inner_state}
                  @server.worker_remove!(state.worker_ref, [force: true], context)
                  {:noreply, state}
                {:wait, inner_state} ->
                  # @TODO force termination conditions needed.
                  state = %Noizu.SimplePool.Worker.State{inner_state: inner_state}
                  :timer.send_after(@check_interval_ms, self(), {:i, {:activity_check, ref}, context})
                  {:noreply, state}
              end
            else
              :timer.send_after(@check_interval_ms, self(), {:i, {:activity_check, ref}, context})
              {:noreply, state}
            end
          else
            {:noreply, state}
          end
        end # end handle_info/:activity_check
      end # end activity_check feature section

      #-------------------------------------------------------------------------
      # Lazy Load Handling Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :lazy_load)) do
        def handle_call({:s, _inner, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          case @worker_state_entity.load(state.worker_ref, context) do
            nil -> {:reply, :initilization_failed, state}
            inner_state ->
              state = %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}
              handle_call(call, from, state)
          end
        end # end handle_call

        def handle_cast({:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          case @worker_state_entity.load(state.worker_ref, context) do
            nil -> {:noreply, state}
            inner_state ->
              state = %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}
              handle_cast(call, state)
          end
        end # end handle_cast

        def handle_info({:s, _inner, context} = call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          case @worker_state_entity.load(state.worker_ref, context) do
            nil -> {:noreply, state}
            inner_state ->
              state = %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}
              handle_info(call, state)
          end
        end # end handle_info
      end

      #-------------------------------------------------------------------------
      # Call Forwarding Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :call_forwarding)) do
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

        def handle_info({:s, inner_call, context} = call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          {reply, inner_state} =  @worker_state_entity.call_forwarding(inner_call, context, inner_state)
          if unquote(MapSet.member?(features, :inactivity_check)) do
            {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
          else
            {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
          end
        end

        def handle_cast({:s, inner_call, context} = call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          {reply, inner_state} =  @worker_state_entity.call_forwarding(inner_call, context, inner_state)
          if unquote(MapSet.member?(features, :inactivity_check)) do
            {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
          else
            {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
          end
        end

        def handle_call({:s, inner_call, context} = call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          {reply, response, inner_state} =  @worker_state_entity.call_forwarding(inner_call, context, from, inner_state)
          if unquote(MapSet.member?(features, :inactivity_check)) do
            {reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
          else
            {reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
          end
        end
      end # end call forwarding feature section
    end # end quote
  end #end __using__

end
