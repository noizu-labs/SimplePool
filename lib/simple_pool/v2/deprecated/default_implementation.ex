#-------------------------------------------------------------------------------
# Author: Keith Brings <keith.brings@noizu.com>
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------
defmodule Noizu.SimplePool.V2.WorkerLookupBehaviour.DefaultImplementation do
  require Logger
  alias Noizu.ElixirCore.OptionSettings
  alias Noizu.ElixirCore.OptionValue
  alias Noizu.ElixirCore.OptionList

  @methods [:host!, :record_event!, :register!, :unregister!, :obtain_lock!, :release_lock!, :process!, :events!, :workers!, :set_node!]
  def prepare_options(options) do
    settings = %OptionSettings{
      option_settings: %{
        only: %OptionList{option: :only, default: @methods, valid_members: @methods, membership_set: true},
        override: %OptionList{option: :override, default: [], valid_members: @methods, membership_set: true},
        dispatch: %OptionValue{option: :dispatch, default:  Application.get_env(:noizu_simple_pool, :default_dispatch, Noizu.SimplePool.DispatchRepo)},
        dispatch_monitor: %OptionValue{option: :dispatch_monitor, default:  Application.get_env(:noizu_simple_pool, :default_dispatch_monitor, Noizu.SimplePool.Dispatch.MonitorRepo)},
        server_monitor:   %OptionValue{option: :server_monitor, default:  Application.get_env(:noizu_simple_pool, :default_server_monitor, Noizu.SimplePool.V2.MonitoringFramework.EnvironmentMonitorService)},
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
      @behaviour Noizu.SimplePool.V2.WorkerLookupBehaviour
      @dispatch unquote(dispatch)
      @dispatch_monitor unquote(dispatch_monitor)
      @server_monitor unquote(server_monitor)
      @registry unquote(registry)
      @pass_thru {__MODULE__, @dispatch, @dispatch_monitor, @server_monitor, @registry}

      if unquote(required.workers!) do
        def workers!(host, service_entity, context), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.workers!(@pass_thru, host, service_entity, context)
        def workers!(host, service_entity, context, options), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.workers!(@pass_thru, host, service_entity, context, options)
      end

      if unquote(required.host!) do
        def host!(ref, server, context), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.host!(@pass_thru, ref, server.base(), server, context)
        def host!(ref, server, context, options), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.host!(@pass_thru, ref, server.base(), server, context, options)
      end

      if unquote(required.record_event!) do
        def record_event!(ref, event, details, context), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.record_event!(@pass_thru, ref, event, details, context)
        def record_event!(ref, event, details, context, options), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.record_event!(@pass_thru, ref, event, details, context, options)
      end

      if unquote(required.events!) do
        def events!(ref, context), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.events!(@pass_thru, ref, context)
        def events!(ref, context, options), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.events!(@pass_thru, ref, context, options)
      end

      if unquote(required.set_node!) do
        def set_node!(ref, context), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.set_node!(@pass_thru, ref, context)
        def set_node!(ref, context, options), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.set_node!(@pass_thru, ref, context, options)
      end

      if unquote(required.register!) do
        def register!(ref, context), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.register!(@pass_thru, ref, context)
        def register!(ref, context, options), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.register!(@pass_thru, ref, context, options)
      end

      if unquote(required.unregister!) do
        def unregister!(ref, context), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.unregister!(@pass_thru, ref, context)
        def unregister!(ref, context, options), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.unregister!(@pass_thru, ref, context, options)
      end

      if unquote(required.obtain_lock!) do
        def obtain_lock!(ref, context), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.obtain_lock!(@pass_thru, ref, context)
        def obtain_lock!(ref, context, options), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.obtain_lock!(@pass_thru, ref, context, options)
      end

      if unquote(required.release_lock!) do
        def release_lock!(ref, context), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.release_lock!(@pass_thru, ref, context)
        def release_lock!(ref, context, options), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.release_lock!(@pass_thru, ref, context, options)
      end

      if unquote(required.process!) do
        def process!(ref, base, server, context), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.process!(@pass_thru, ref, base, server, context)
        def process!(ref, base, server, context, options), do: Noizu.SimplePool.V2.WorkerLookupBehaviourDefault.process!(@pass_thru, ref, base, server, context, options)
      end

    end
  end

end