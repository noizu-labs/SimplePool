#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.WorkerLookupBehaviour do
  @type lock_response :: {:ack, record :: any} | {:nack, {details :: any, record :: any}} | {:nack, details :: any} | {:error, details :: any}

  @callback workers!(any, any, any, any) :: {:ack, list} | any

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


    def default_workers!({_mod, d, _m, _sm, _r}, host, service_entity, context, options \\ %{}) do
      d.workers!(host, service_entity, context, options)
    end

    def default_host!({_mod, d, _m, sm, _r}, ref, base, _server, context, options \\ %{spawn: true}) do

      case d.get!(ref, context, options) do
        nil ->
          if options[:spawn] do
            options_b = update_in(options, [:lock], &(Map.merge(&1 || %{}, %{server: :pending, type: :spawn})))
            entity = d.new(ref, context, options_b)
                     |> put_in([Access.key(:lock)], d.prepare_lock(options_b, true))
                     |> d.create!(context, options_b)


            case sm.select_host(ref, base, context, options_b) do
              {:ack, host} ->
                entity = entity
                         |> put_in([Access.key(:server)], host)
                         |> put_in([Access.key(:lock)], nil)
                         |> d.update!(context, options_b)
                {:ack, entity.server}
              {:nack, details} ->
                entity = entity
                         |> put_in([Access.key(:lock)], nil)
                         |> d.update!(context, options_b)
                {:error, {:host_pick, {:nack, details}}}
              o ->
                o
            end
          else
            {:nack, :no_registered_host}
          end
        v when is_atom(v) -> {:error, {:repo, v}}
        {:error, details} -> {:error, details}
        entity ->
          if entity.server == :pending do
            options_b = update_in(options, [:lock], &(Map.merge(&1 || %{}, %{server: :pending, type: :spawn})))
            case d.obtain_lock!(ref, context, options_b) do
              {:ack, _lock} ->
                case sm.select_host(ref, base, context, options_b) do
                  {:ack, host} ->
                    entity = entity
                             |> put_in([Access.key(:server)], host)
                             |> put_in([Access.key(:lock)], nil)
                             |> d.update!(context, options_b)
                    {:ack, entity.server}
                  {:nack, details} -> {:error, {:host_pick, {:nack, details}}}
                  o -> o
                end
              {:nack, details} -> {:error, {:obtain_lock, {:nack, details}}}
            end
          else
            {:ack, entity.server}
          end
      end
    end

    def default_record_event!({_mod, _d, m,_sm, _r}, ref, event, details, context, options \\ %{}) do
      Logger.info(fn -> {"[RecordEvent #{inspect event}] #{node()} #{inspect %{ref: ref, event: event, details: details}}", CallingContext.metadata(context)} end)
      m.new(ref, event, details, context, options)
      |> m.create!(context, options)
    end

    def default_events!({_mod, _d, m, _sm, _r}, ref, context, _options \\ %{}) do
      m.get!(ref, context)
    end

    def default_set_node!({mod, d, _m, _sm, r}, ref, context, options \\ %{}) do
      Task.async(fn ->
                    case d.get!(ref, context, options) do
                      nil -> :unexpected
                      entity ->
                        if entity.server != node() do
                          entity
                          |> put_in([Access.key(:server)], node()) #@TODO standardize naming conventions.
                          |> d.update!(context, options)
                        end
                    end

                    inner = Task.async(fn ->
                      # delay before releasing lock to allow a flood of node updates to update before removing locks.
                      Process.sleep(60_000)
                      # Release lock off main thread
                      options_b = %{lock: %{type: :init}, conditional_checkout: fn(x) ->
                        case x do
                          %{lock: {{_s, _p}, :transfer, _t}} -> true
                          %{lock: {{_s, _p}, :spawn, _t}} -> true
                          %{lock: {{_s, _p}, :init, _t}} -> true
                          _ -> false
                        end
                      end}
                      options_b = Map.merge(options_b, options)
                      {:ack, mod.release_lock!(ref, context, options_b)}
                    end)
                    {:ack, inner}
      end)
    end

    def default_register!({_mod, _d, _m, _sm, r}, ref, _context, _options \\ %{}) do
      #if options[:set_node] do
      #  task = mod.set_node!(ref, context, options)
      #  Registry.register(r, {:worker, ref}, :process)
      #  if options[:set_node_yield] do
      #    Task.yield(task, options[:set_node_yield])
      #  end
      #  task
      #else
        Registry.register(r, {:worker, ref}, :process)
      #end
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

    def default_process!({mod, d, _m, _s, r}, ref, base, server, context, options \\ %{}) do
      record = options[:dispatch_record] || d.get!(ref, context, options)
      case record do
        nil ->
          case mod.host!(ref, server, context, options) do
            {:ack, host} ->
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
                            {:ack, pid} -> {:ack, pid}
                            o -> o
                          end
                        o -> o
                      end
                    else
                      {:nack, :not_registered}
                    end
                  [{pid, _v}] -> {:ack, pid}
                  v ->
                    #@PRI-0 disabled until rate limite added - mod.record_event!(ref, :registry_lookup_fail, v, context, options)
                    {:error, {:unexpected_response, v}}
                end
              else
                options_b = put_in(options, [:dispatch_record], record)
                case :rpc.call(host, mod, :process!, [ref, base, server, context, options_b], 5_000) do
                  {:ack, process} -> {:ack, process}
                  {:nack, details} -> {:nack, details}
                  {:error, details} -> {:error, details}
                  {:badrpc, details} ->
                    #@PRI-0 disabled until rate limite added - mod.record_event!(ref, :process_check_fail, {:badrpc, details}, context, options)
                    {:error, {:badrpc, details}}
                  o -> {:error, o}
                end
              end

            v -> {:nack, {:host_error, v}}
          end

        %{server: host} ->
          cond do
            host == :pending ->
              if options[:spawn] do
                 host2 = mod.host!(ref, server, context, options)
                 if host2 == node() do
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
                         {:ack, pid} -> {:ack, pid}
                         o -> o
                       end
                     o -> o
                   end
                 else
                   :rpc.call(host2, mod, :process!, [ref, base, server, context, options], 5_000)
                 end
              else
                {:nack, :not_registered}
              end
            host == node() ->
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
                          {:ack, pid} -> {:ack, pid}
                          o -> o
                        end
                      o -> o
                    end
                  else
                    {:nack, :not_registered}
                  end
                [{pid, _v}] -> {:ack, pid}
                v ->
                  #@PRI-0 disabled until rate limite added - mod.record_event!(ref, :registry_lookup_fail, v, context, options)
                  {:error, {:unexpected_response, v}}
              end
            true ->
              options_b = put_in(options, [:dispatch_record], record)
              case :rpc.call(host, mod, :process!, [ref, base, server, context, options_b], 5_000) do
                {:ack, process} -> {:ack, process}
                {:nack, details} -> {:nack, details}
                {:error, details} -> {:error, details}
                {:badrpc, details} ->
                  #@PRI-0 disabled until rate limite added - mod.record_event!(ref, :process_check_fail, {:badrpc, details}, context, options)
                  {:error, {:badrpc, details}}
                o -> {:error, o}
              end
          end
      end
    end

    @methods [:host!, :record_event!, :register!, :unregister!, :obtain_lock!, :release_lock!, :process!, :events!, :workers!, :set_node!]
    def prepare_options(options) do
      settings = %OptionSettings{
        option_settings: %{
          only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
          override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
          dispatch: %OptionValue{option: :dispatch, default:  Application.get_env(:noizu_simple_pool, :default_dispatch, Noizu.SimplePool.DispatchRepo)},
          dispatch_monitor: %OptionValue{option: :dispatch_monitor, default:  Application.get_env(:noizu_simple_pool, :default_dispatch_monitor, Noizu.SimplePool.Dispatch.MonitorRepo)},
          server_monitor:   %OptionValue{option: :server_monitor, default:  Application.get_env(:noizu_simple_pool, :default_server_monitor, Noizu.SimplePool.MonitoringFramework.MonitorBehaviour.Default)},
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

        if unquote(required.workers!) do
          def workers!(host, service_entity, context), do: default_workers!(@pass_thru, host, service_entity, context)
          def workers!(host, service_entity, context, options), do: default_workers!(@pass_thru, host, service_entity, context, options)
        end

        if unquote(required.host!) do
          def host!(ref, server, context), do: default_host!(@pass_thru, ref, server.base(), server, context)
          def host!(ref, server, context, options), do: default_host!(@pass_thru, ref, server.base(), server, context, options)
        end

        if unquote(required.record_event!) do
          def record_event!(ref, event, details, context), do: default_record_event!(@pass_thru, ref, event, details, context)
          def record_event!(ref, event, details, context, options), do: default_record_event!(@pass_thru, ref, event, details, context, options)
        end

        if unquote(required.events!) do
          def events!(ref, context), do: default_events!(@pass_thru, ref, context)
          def events!(ref, context, options), do: default_events!(@pass_thru, ref, context, options)
        end

        if unquote(required.set_node!) do
          def set_node!(ref, context), do: default_set_node!(@pass_thru, ref, context)
          def set_node!(ref, context, options), do: default_set_node!(@pass_thru, ref, context, options)
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
          def process!(ref, base, server, context), do: default_process!(@pass_thru, ref, base, server, context)
          def process!(ref, base, server, context, options), do: default_process!(@pass_thru, ref, base, server, context, options)
        end
      end
    end

  end
end
