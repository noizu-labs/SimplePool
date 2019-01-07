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
        server_monitor:   %OptionValue{option: :server_monitor, default:  Application.get_env(:noizu_simple_pool, :default_server_monitor, Noizu.SimplePool.MonitoringFramework.MonitorBehaviour.Default)},
        registry:   %OptionValue{option: :registry, default:  Application.get_env(:noizu_simple_pool, :default_registry, Noizu.SimplePool.DispatchRegister)},
        implementation:   %OptionValue{option: :implementation, default:  Application.get_env(:noizu_simple_pool, :default_worker_lookup, Noizu.SimplePool.WorkerLookupBehaviourDefault)},
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
    implementation = options.implementation
    required = options.required
    
    quote do
      import unquote(__MODULE__)
      @behaviour Noizu.SimplePool.WorkerLookupBehaviour
      @dispatch unquote(dispatch)
      @dispatch_monitor unquote(dispatch_monitor)
      @server_monitor unquote(server_monitor)
      @registry unquote(registry)
      @implementation unquote(implementation)
      @pass_thru {__MODULE__, @dispatch, @dispatch_monitor, @server_monitor, @registry}
      
      def workers!(host, service_entity, context), do: _workers(host, service_entity, context)
      def workers!(host, service_entity, context, options), do: _workers!(@pass_thru, host, service_entity, context, options)
      
      def host!(ref, server, context), do: _host!(@pass_thru, ref, server.base(), server, context)
      def host!(ref, server, context, options), do: _host!(@pass_thru, ref, server.base(), server, context, options)
      
      def record_event!(ref, event, details, context), do: _record_event!(@pass_thru, ref, event, details, context)
      def record_event!(ref, event, details, context, options), do: _record_event!(@pass_thru, ref, event, details, context, options)
      
      def events!(ref, context), do: _events!(@pass_thru, ref, context)
      def events!(ref, context, options), do: _events!(@pass_thru, ref, context, options)
      
      def set_node!(ref, context), do: _set_node!(@pass_thru, ref, context)
      def set_node!(ref, context, options), do: _set_node!(@pass_thru, ref, context, options)
      
      def register!(ref, context), do: _register!(@pass_thru, ref, context)
      def register!(ref, context, options), do: _register!(@pass_thru, ref, context, options)
      
      def unregister!(ref, context), do: _unregister!(@pass_thru, ref, context)
      def unregister!(ref, context, options), do: _unregister!(@pass_thru, ref, context, options)
      
      def obtain_lock!(ref, context), do: _obtain_lock!(@pass_thru, ref, context)
      def obtain_lock!(ref, context, options), do: _obtain_lock!(@pass_thru, ref, context, options)
      
      def release_lock!(ref, context), do: _release_lock!(@pass_thru, ref, context)
      def release_lock!(ref, context, options), do: _release_lock!(@pass_thru, ref, context, options)
      
      def process!(ref, base, server, context), do: _process!(@pass_thru, ref, base, server, context)
      def process!(ref, base, server, context, options), do: _process!(@pass_thru, ref, base, server, context, options)


      defdelegate _workers!(pass_through, host, service_entity, context), to: @implementation, as: :workers!
      defdelegate _workers!(pass_through, host, service_entity, context, options), to: @implementation, as: :workers!
      
      defdelegate _host!(pass_through, ref, server, context), to: @implementation, as: :host!
      defdelegate _host!(pass_through, ref, server, context, options), to: @implementation, as: :host!

      defdelegate _record_event!(pass_through, ref, event, details, context), to: @implementation, as: :record_event!
      defdelegate _record_event!(pass_through,ref, event, details, context, options), to: @implementation, as: :record_event!

      defdelegate _events!(pass_through,ref, context), to: @implementation, as: :events!
      defdelegate _events!(pass_through,ref, context, options), to: @implementation, as: :events!

      defdelegate _set_node!(pass_through,ref, context), to: @implementation, as: :set_node!
      defdelegate _set_node!(pass_through,ref, context, options), to: @implementation, as: :set_node!

      defdelegate _register!(pass_through,ref, context), to: @implementation, as: :register!
      defdelegate _register!(pass_through,ref, context, options), to: @implementation, as: :register!

      defdelegate _unregister!(pass_through,ref, context), to: @implementation, as: :unregister!
      defdelegate _unregister!(pass_through,ref, context, options), to: @implementation, as: :unregister!

      defdelegate _obtain_lock!(pass_through,ref, context), to: @implementation, as: :obtain_lock!
      defdelegate _obtain_lock!(pass_through,ref, context, options), to: @implementation, as: :obtain_lock!

      defdelegate _release_lock!(pass_through,ref, context), to: @implementation, as: :release_lock!
      defdelegate _release_lock!(pass_through,ref, context, options), to: @implementation, as: :release_lock!

      defdelegate _process!(pass_through,ref, base, server, context), to: @implementation, as: :process!
      defdelegate _process!(pass_through,ref, base, server, context, options), to: @implementation, as: :process!



      defoverridable [
        workers!: 3,
        workers!: 4,
        host!: 3,
        host!: 4,
        record_event!: 4,
        record_event!: 5,
        events!: 2,
        events!: 3,
        set_node!: 2,
        set_node!: 3,
        register!: 2,
        register!: 3,
        unregister: 2,
        unregister: 3,
        obtain_lock!: 2,
        obtain_lock!: 3,
        release_lock!: 2,
        release_lock!: 3,
        process!: 4,
        process!: 5
      ]
    end
  end

end