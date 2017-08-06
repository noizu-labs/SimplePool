defmodule Noizu.SimplePool.WorkerBehaviour do
  alias Noizu.SimplePool.OptionSettings
  alias Noizu.SimplePool.OptionValue
  alias Noizu.SimplePool.OptionList
  
  @methods([:start_link, :init, :terminate])
  @features([:auto_identifier, :lazy_load, :inactivitiy_check, :s_redirect])
  @default_features([:lazy_load, :s_redirect, :inactivity_check])
  @default_check_interval_ms(1000 * 60 * 2)
  @default_kill_interval_ms(1000 * 60 * 10)

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
    check_interval_ms = options.check_interval_ms
    kill_interval_ms = options.kill_interval_ms

    quote do
      import unquote(__MODULE__)
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
            @base.banner("START_LINK #{__MODULE__} (#{inspect nmid})") |> IO.puts()
          end
          GenServer.start_link(__MODULE__, ref)
        end
      end # end start_link

      # @terminate
      if (unquote(required.terminate)) do
        def terminate(reason, state) do
          if (unquote(verbose)) do
            @base.banner("TERMINATE #{__MODULE__} (#{inspect state.worker_ref}") |> IO.puts()
          end
          # @TODO perform dereg in server method.
          @server.worker_lookup().dereg_worker!(@base, state.worker_ref)
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
            @base.banner("INIT #{__MODULE__} (#{inspect ref }") |> IO.puts()
          end
          @server.worker_lookup().reg_worker!(@base, ref, self())
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
      if unquote(MapSet.member?(features, :s_redirect)) do
        def handle_cast({:s_cast, {mod, nmid}, call}, state) do
          if (mod == @base) do
            handle_cast(call, state)
          else
            @server.worker_lookup().clear_process!(mod, nmid, {self(), node})
            server = Module.concat(mod, "Server")
            server.s_cast(nmid, call)
            {:noreply, state}
          end
        end # end handle_cast/:s_cast

        def handle_cast({:s_cast!, {mod, nmid}, call}, state) do
          if (mod == @base) do
            handle_cast(call, state)
          else
            @server.worker_lookup().clear_process!(mod, nmid, {self(), node})
            server = Module.concat(mod, "Server")
            server.s_cast!(nmid, call)
            {:noreply, state}
          end
        end # end handle_cast/:s_cast!

        def handle_call({:s_call, {mod, nmid, time_out}, call}, from, state) do
          if (mod == @base) do
            handle_call(call, from, state)
          else
            @server.worker_lookup().clear_process!(mod, nmid, {self(), node})
            {:reply, :s_retry, state}
          end
        end # end handle_call/:s_call

        def handle_call({:s_call!, {mod, nmid, time_out}, call}, from, state) do
          if (mod == @base) do
            handle_call(call, from, state)
          else
            @server.worker_lookup().clear_process!(mod, nmid, {self(), node})
            {:reply, :s_retry, state}
          end
        end # end handle_call/:s_call!
      end # end s_redirect

      #-------------------------------------------------------------------------
      # Inactivity Check Handling Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :inactivity_check)) do
        def handle_info({:activity_check, ref}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          if ref == state.worker_ref do
            if ((state.last_activity == nil) || ((state.last_activity + @kill_interval_s) < :os.system_time(:seconds))) do
              @server.remove!(state.worker_ref)
            else
              :timer.send_after(@check_interval_ms, self(), {:activity_check, ref})
            end
            {:noreply, state}
          else
            {:noreply, state}
          end
        end # end handle_info/:activity_check

        def handle_info({:activity_check, ref}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          if ref == state.worker_ref do
            if ((state.last_activity == nil) || ((state.last_activity + @kill_interval_s) < :os.system_time(:seconds))) do
              case @worker_state_entity.shutdown(state.inner_state) do
                {:ok, inner_state} ->
                  state = %Noizu.SimplePool.Worker.State{inner_state: inner_state}
                  @server.remove!(state.worker_ref)
                  {:noreply, state}
                {:wait, inner_state} ->
                  # @TODO force termination conditions needed.
                  state = %Noizu.SimplePool.Worker.State{inner_state: inner_state}
                  :timer.send_after(@check_interval_ms, self(), {:activity_check, ref})
                  {:noreply, state}
              end
            else
              :timer.send_after(@check_interval_ms, self(), {:activity_check, ref})
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
        def handle_call(any_call, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          case @worker_state_entity.load(state.worker_ref) do
            nil -> {:reply, :initilization_failed, state}
            inner_state ->
              state = %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}
              handle_call(any_call, from, state)
          end
        end # end handle_call

        def handle_cast(any_call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          case @worker_state_entity.load(state.worker_ref) do
            nil -> {:noreply, state}
            inner_state ->
              state = %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}
              handle_cast(any_call, state)
          end
        end # end handle_cast

        def handle_info(any_call, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          case @worker_state_entity.load(state.worker_ref) do
            nil -> {:noreply, state}
            inner_state ->
              state = %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}
              handle_info(any_call, state)
          end
        end # end handle_info
      end

      #-------------------------------------------------------------------------
      # Call Forwarding Feature Section
      #-------------------------------------------------------------------------
      if unquote(MapSet.member?(features, :call_forwarding)) do
        def handle_cast({:load}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
          case @worker_state_entity.load(state.worker_ref) do
            nil -> {:noreply, state}
            inner_state ->
              if unquote(MapSet.member?(features, :inactivity_check)) do
                {:noreply, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
              else
                {:noreply, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state}}
              end
          end
        end

        def handle_info(call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          {reply, inner_state} =  @worker_state_entity.call_forwarding(:info, inner_state, call)
          if unquote(MapSet.member?(features, :inactivity_check)) do
            {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
          else
            {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
          end
        end

        def handle_cast(call, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          {reply, inner_state} =  @worker_state_entity.call_forwarding(:cast, inner_state, call)
          if unquote(MapSet.member?(features, :inactivity_check)) do
            {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
          else
            {reply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
          end
        end

        def handle_call(call, from, %Noizu.SimplePool.Worker.State{initialized: true, inner_state: inner_state} = state) do
          {reply, response, inner_state} =  @worker_state_entity.call_forwarding(:call, inner_state, call, from)
          if unquote(MapSet.member?(features, :inactivity_check)) do
            {reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: :os.system_time(:seconds)}}
          else
            {reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
          end
        end
      end # end call forwarding feature section
      #@before_compile unquote(__MODULE__)
    end # end quote
  end #end __using__

  #################
  #defmacro __before_compile__(_env) do
  #  quote do
  #  end # end quote
  #end # end __before_compile__
  #######################

end
