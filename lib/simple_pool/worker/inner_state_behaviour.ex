defmodule Noizu.SimplePool.InnerStateBehaviour do

  @callback call_forwarding(call :: any, context :: any, state :: any) :: {:noreply, state :: any}
  @callback call_forwarding(call :: any, context :: any, from :: any,  state :: any) :: {atom, reply :: any, state :: any}
  @callback fetch(this :: any, options :: any, context :: any) :: {:reply, this :: any, this :: any}

  @callback load(ref :: any) ::  any
  @callback load(ref :: any, context :: any) :: any
  @callback load(ref :: any, options :: any, context :: any) :: any

  @callback terminate_hook(reason :: any,  Noizu.SimplePool.Worker.State.t) :: {:ok, Noizu.SimplePool.Worker.State.t}
  @callback shutdown(Noizu.SimplePool.Worker.State.t, options :: any, context :: any, from :: any) :: {:ok | :wait, Noizu.SimplePool.Worker.State.t}

  alias Noizu.SimplePool.OptionSettings
  alias Noizu.SimplePool.OptionValue
  alias Noizu.SimplePool.OptionList

  @required_methods([:call_forwarding, :load])
  @provided_methods([:call_forwarding_catchall, :fetch, :shutdown, :terminate_hook, :get_direct_link!])

  @methods(@required_methods ++ @provided_methods)
  @features([:auto_identifier, :lazy_load, :inactivitiy_check, :s_redirect])
  @default_features([:lazy_load, :s_redirect, :inactivity_check])

  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        pool: %OptionValue{option: :pool, required: true},
        features: %OptionList{option: :features, default: Application.get_env(Noizu.SimplePool, :default_features, @default_features), valid_members: @features, membership_set: false},
        only: %OptionList{option: :only, default: @provided_methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
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
    pool = options.pool

    quote do
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.InnerStateBehaviour
      @base(unquote(Macro.expand(pool, __CALLER__)))
      @worker(Module.concat([@base, "Worker"]))
      @worker_supervisor(Module.concat([@base, "WorkerSupervisor"]))
      @server(Module.concat([@base, "Server"]))
      @pool_supervisor(Module.concat([@base, "PoolSupervisor"]))
      @simple_pool_group({@base, @worker, @worker_supervisor, @server, @pool_supervisor})

      alias Noizu.SimplePool.Worker.Link

      if (unquote(required.get_direct_link!)) do
        def get_direct_link!(ref, context) do
          @server.get_direct_link!(ref, context)
        end
      end

      if (unquote(required.fetch)) do
        def fetch(%__MODULE__{} = this, _options, context), do: {:reply, this, this}
      end

      if (unquote(required.call_forwarding_catchall)) do
        # Default Call Forwarding Catch All
        def call_forwarding_catchall(call, context, _from, %__MODULE__{} = this) do
          if context do
            Logger.warn("[#{context.token}] Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
          else
            Logger.warn("[NO_TOKEN] Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
          end
          {:reply, :unsupported_call, this}
        end

        def call_forwarding_catchall(call, context, %__MODULE__{} = this) do
          if context do
            Logger.warn("[#{context.token}] Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
          else
            Logger.warn("[NO_TOKEN] Unhandle Call #{inspect {call, __MODULE__.ref(this)}}")
          end
          {:noreply, this}
        end
      end

      if (unquote(required.shutdown)) do
        def shutdown(%Noizu.SimplePool.Worker.State{} = state, _options \\ [], context \\ nil, _from \\ nil) do
          {:ok, state}
        end
      end

      if (unquote(required.terminate_hook)) do
        def terminate_hook(reason, state) do
          {:ok, state}
        end
      end

    end # end quote
  end # end using
end # end module
