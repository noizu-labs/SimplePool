#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.WorkerLookupBehaviourDefault do
    require Logger
    alias Noizu.ElixirCore.CallingContext

    def workers!({_mod, d, _m, _sm, _r}, host, service_entity, context, options \\ %{}) do
      d.workers!(host, service_entity, context, options)
    end

    def host!({_mod, d, _m, sm, _r}, ref, base, _server, context, options \\ %{spawn: true}) do
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
                  _entity = entity
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
            if options[:dirty] do
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
            else
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
            end
          else
            {:ack, entity.server}
          end
      end
    end

    def record_event!({_mod, _d, m,_sm, _r}, ref, event, details, context, options \\ %{}) do
      Logger.info(fn -> {"[RecordEvent #{inspect event}] #{node()} #{inspect %{ref: ref, event: event, details: details}}", CallingContext.metadata(context)} end)
      m.new(ref, event, details, context, options)
      |> m.create!(context, options)
    end

    def events!({_mod, _d, m, _sm, _r}, ref, context, _options \\ %{}) do
      m.get!(ref, context)
    end

    def set_node!({mod, d, _m, _sm, _r}, ref, context, options \\ %{}) do
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

    def register!({_mod, _d, _m, _sm, r}, ref, _context, _options \\ %{}) do
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

    def unregister!({_mod, _d, _m, _s, r}, ref, _context, _options \\ %{}) do
      Registry.unregister(r, ref)
    end

    def obtain_lock!({_mod, d, _m, _s, _r}, ref, context, options \\ %{}) do
      options_b = update_in(options, [:lock], &(Map.merge(&1 || %{}, %{type: :general})))
      d.obtain_lock!(ref, context, options_b)
    end

    def release_lock!({_mod, d, _m, _s, _r}, ref, context, options \\ %{}) do
      d.release_lock!(ref, context, options)
    end

    def process!({mod, d, _m, _s, r}, ref, base, server, context, options \\ %{}) do
      record = options[:dispatch_record] || d.get!(ref, context, options)
      case record do
        nil ->
          case mod.host!(ref, server, context, options) do
            {:ack, host} ->
              if host == node() do
                case Registry.lookup(r, {:worker, ref}) do
                  [] ->
                    if options[:spawn] do
                      if options[:dirty] do
                        case server.worker_sup_start(ref, context) do
                          {:ok, pid} -> {:ack, pid}
                          {:ack, pid} -> {:ack, pid}
                          o -> o
                        end
                      else
                        options_b = %{lock: %{type: :init}, conditional_checkout: fn(x) ->
                          case x.lock do
                            {{_s, _p}, :spawn, _t} -> true
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
              timeout = options_b[:timeout] || 30_000
              case :rpc.call(host, mod, :process!, [ref, base, server, context, options_b], timeout) do
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
end
