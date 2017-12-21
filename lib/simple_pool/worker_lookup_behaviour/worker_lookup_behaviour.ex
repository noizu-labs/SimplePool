#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.WorkerLookupBehaviour do
  @type lock_response :: {:ack, record :: any} | {:nack, {details :: any, record :: any}} | {:nack, details :: any} | {:error, details :: any}

  @callback host!(ref :: tuple, server :: module, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: {:ok, atom} | {:spawn, atom} | {:error, details :: any} | {:restricted, atom}
  @callback record_event!(ref :: tuple, event :: atom, details :: any, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: any
  @callback events!(ref :: tuple, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: list

  @callback register!(ref :: tuple, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: any
  @callback unregister!(ref :: tuple, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: any

  @callback process!(ref :: tuple, server :: module, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: lock_response
  @callback obtain_lock!(ref :: tuple, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: lock_response
  @callback release_lock!(ref :: tuple, Noizu.ElixirCore.Context.t | nil, opts :: Map.t) :: lock_response

  #-------------------------------------------------------------------------------
  # Author: Keith Brings <keith.brings@noizu.com>
  # Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
  #-------------------------------------------------------------------------------

  defmodule DefaultImplementation do
    require Logger
    alias Noizu.ElixirCore.OptionSettings
    alias Noizu.ElixirCore.OptionValue
    alias Noizu.ElixirCore.OptionList
    alias Noizu.ElixirCore.CallingContext

    def default_host!({_mod, d, _m, sm, _r}, ref, server, context, options \\ %{spawn: true}) do
      case d.get!(ref, context, options) do
        nil ->
          if options[:spawn] do
            options_b = update_in(options, [:lock], &(Map.merge(&1 || %{}, %{server: :pending, type: :spawn})))
            entity = d.new(ref, context, options_b)
                     |> put_in([Access.key(:lock)], d.prepare_lock(options_b, true))
                     |> d.create!(context, options_b)
            case sm.select_host(ref, server, context, options_b) do
              {:ack, host} ->
                entity = entity
                         |> put_in([Access.key(:server)], host)
                         |> d.update!(context, options_b)
                {:ack, entity.server}
              {:nack, details} -> {:error, {:host_pick, {:nack, details}}}
              o -> o
            end
          else
            {:nack, :no_registered_host}
          end
        v when is_atom(v) -> {:error, {:repo, v}}
        {:error, details} -> {:error, details}
        v -> {:ack, v.server}
      end
    end

    def default_record_event!({_mod, _d, m,_sm, _r}, ref, event, details, context, options \\ %{}) do
      Logger.info(fn -> {"#{inspect %{ref: ref, event: event, details: details}}", CallingContext.metadata(context)} end)
      m.new(ref, event, details, context, options)
      |> m.create!(context, options)
    end

    def default_events!({_mod, _d, m, _sm, _r}, ref, context, _options \\ %{}) do
      m.get!(ref, context)
    end

    def default_register!({mod, _d, _m, _sm, r}, ref, context, _options \\ %{}) do
      r = Registry.register(r, {:worker, ref}, :process)
      options_b = %{lock: %{type: :init}, conditional_checkout: fn(x) ->
        case x do
          %{lock: {{_s, _p}, :spawn, _t}} -> true
          %{lock: {{_s, _p}, :init, _t}} -> true
          _ -> false
        end
      end}
      mod.release_lock!(ref, context, options_b)
      r
    end

    def default_unregister!({_mod, _d, _m, _s, r}, ref, _context, _options \\ %{}) do
      Registry.unregister(r, ref)
    end

    def default_obtain_lock!({_mod, d, _m, _s, _r}, ref, context, options \\ %{}) do
      options_b = update_in(options, [:lock], &(Map.merge(&1 || %{}, %{type: :general})))
      d.obtain_lock!(ref, context, options_b)
    end

    def default_release_lock!({_mod, d, _m, _s, _r}, ref, context, options \\ %{}) do
      d.release_lock!(ref, context, options)
    end

    def default_process!({mod, d, _m, _s, r}, ref, server, context, options \\ %{}) do
      record = options[:dispatch_record] || d.get!(ref, context, options)
      case record do
        %{server: host} ->
          if host == node() do
            case Registry.lookup(r, {:worker, ref}) do
              [] ->
                if options[:spawn] do
                  options_b = %{lock: %{type: :init}, conditional_checkout: fn(x) ->
                    case x do
                      %{lock: {{_s, _p}, :spawn, _t}} -> true
                      _ -> false
                    end
                  end}
                  case mod.obtain_lock!(ref, context, options_b) do
                    {:ack, _lock} ->
                      case server.worker_sup_start(ref, context) do
                        {:ok, pid} -> {:ack, pid}
                        o -> o
                      end
                    o -> o
                  end
                else
                  {:nack, :not_registered}
                end
              [{pid, _v}] -> {:ack, pid}
              v ->
                mod.record_event!(ref, :registry_lookup_fail, v, context, options)
                {:error, {:unexpected_response, v}}
            end
          else
            options_b = put_in(options, [:dispatch_record], r)
            case :rpc.call(host, mod, :process!, [ref, context, options_b], 1_000) do
              {:ack, process} -> {:ack, process}
              {:nack, details} -> {:nack, details}
              {:error, details} -> {:error, details}
              {:badrpc, details} ->
                mod.record_event!(ref, :process_check_fail, {:badrpc, details}, context, options)
                {:error, {:badrpc, details}}
              o -> {:error, o}
            end
          end
      end
    end

    @methods [:host!, :record_event!, :register!, :unregister!, :obtain_lock!, :release_lock!, :process!, :events!]
    def prepare_options(options) do
      settings = %OptionSettings{
        option_settings: %{
          only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
          override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
          dispatch: %OptionValue{option: :dispatch, default:  Application.get_env(:noizu_simple_pool, :default_dispatch, Noizu.SimplePool.DispatchRepo)},
          dispatch_monitor: %OptionValue{option: :dispatch_monitor, default:  Application.get_env(:noizu_simple_pool, :default_dispatch_monitor, Noizu.SimplePool.Dispatch.MonitorRepo)},
          server_monitor:   %OptionValue{option: :server_monitor, default:  Application.get_env(:noizu_simple_pool, :default_server_monitor, Noizu.SimplePool.ServerMonitorBehaviour.DefaultImplementation)},
          registry:   %OptionValue{option: :registry, default:  Application.get_env(:noizu_simple_pool, :default_registry, Noizu.SimplePool.DispatchRegister)},
        }
      }
      initial = OptionSettings.expand(settings, options)
      modifications = Map.put(initial.effective_options, :required, List.foldl(@methods, %{}, fn(x, acc) -> Map.put(acc, x, initial.effective_options.only[x] && !initial.effective_options.override[x]) end))
      %OptionSettings{initial| effective_options: Map.merge(initial.effective_options, modifications)}
    end

    defmacro __using__(options) do
      option_settings = prepare_options(options)
      options = option_settings.effective_options
      dispatch = options.dispatch
      dispatch_monitor = options.dispatch_monitor
      server_monitor = options.server_monitor
      registry = options.registry
      required = options.required

      quote do
        import unquote(__MODULE__)
        @behaviour Noizu.SimplePool.WorkerLookupBehaviour
        @dispatch unquote(dispatch)
        @dispatch_monitor unquote(dispatch_monitor)
        @server_monitor unquote(server_monitor)
        @registry unquote(registry)
        @pass_thru {__MODULE__, @dispatch, @dispatch_monitor, @server_monitor, @registry}

        if unquote(required.host!) do
          def host!(ref, server, context), do: default_host!(@pass_thru, ref, server, context)
          def host!(ref, server, context, options), do: default_host!(@pass_thru, ref, server, context, options)
        end

        if unquote(required.record_event!) do
          def record_event!(ref, event, details, context), do: default_record_event!(@pass_thru, ref, event, details, context)
          def record_event!(ref, event, details, context, options), do: default_record_event!(@pass_thru, ref, event, details, context, options)
        end

        if unquote(required.events!) do
          def events!(ref, context), do: default_events!(@pass_thru, ref, context)
          def events!(ref, context, options), do: default_events!(@pass_thru, ref, context, options)
        end

        if unquote(required.register!) do
          def register!(ref, context), do: default_register!(@pass_thru, ref, context)
          def register!(ref, context, options), do: default_register!(@pass_thru, ref, context, options)
        end

        if unquote(required.unregister!) do
          def unregister!(ref, context), do: default_unregister!(@pass_thru, ref, context)
          def unregister!(ref, context, options), do: default_unregister!(@pass_thru, ref, context, options)
        end

        if unquote(required.obtain_lock!) do
          def obtain_lock!(ref, context), do: default_obtain_lock!(@pass_thru, ref, context)
          def obtain_lock!(ref, context, options), do: default_obtain_lock!(@pass_thru, ref, context, options)
        end

        if unquote(required.release_lock!) do
          def release_lock!(ref, context), do: default_release_lock!(@pass_thru, ref, context)
          def release_lock!(ref, context, options), do: default_release_lock!(@pass_thru, ref, context, options)
        end

        if unquote(required.process!) do
          def process!(ref, server, context), do: default_process!(@pass_thru, ref, server, context)
          def process!(ref, server, context, options), do: default_process!(@pass_thru, ref, server, context, options)
        end
      end
    end

  end
end