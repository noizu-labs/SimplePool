#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Server.Router.DefaultImplementation do
  def extended_call(module, ref, timeout, call, context) do
    # @TODO @PRI-0
    # if redirect router then: {:s_call!, {__MODULE__, ref, timeout}, {:s, call, context}}
    # else: {:s, call, context}
    {:s_call!, {module, ref, timeout}, {:s, call, context}}
  end

  def self_call(module, call, context , options), do: throw "PRI0"
  def self_cast(module, call, context , options), do: throw "PRI0"

  def internal_system_call(module, call, context , options), do: throw "PRI0"
  def internal_system_cast(module, call, context , options), do: throw "PRI0"

  def internal_call(module, call, context , options), do: throw "PRI0"
  def internal_cast(module, call, context , options), do: throw "PRI0"

  def remote_system_call(module, remote_node, call, context, options), do: throw "PRI0"
  def remote_system_cast(module, remote_node, call, context, options), do: throw "PRI0"

  def remote_call(module, remote_node, call, context , options), do: throw "PRI0"
  def remote_cast(module, remote_node, call, context , options), do: throw "PRI0"

  def get_direct_link!(module, ref, context, options), do: throw "PRI0"
  def s_call_unsafe(module, ref, extended_call, context, options , timeout), do: throw "PRI0"
  def s_cast_unsafe(module, ref, extended_call, context, options), do: throw "PRI0"
  def route_call(module, envelope, from, state), do: throw "PRI0"
  def route_cast(module, envelope, state), do: throw "PRI0"
  def route_info(module, envelope, state), do: throw "PRI0"
  def extended_call(module, ref, timeout, call, context), do: throw "PRI0"
  def s_call!(module, identifier, call, context, options), do: throw "PRI0"
  def s_call(module, identifier, call, context, options), do: throw "PRI0"
  def s_cast!(module, identifier, call, context, options), do: throw "PRI0"
  def s_cast(module, identifier, call, context, options), do: throw "PRI0"
  def link_forward!(module, link, call, context, options), do: throw "PRI0"


end