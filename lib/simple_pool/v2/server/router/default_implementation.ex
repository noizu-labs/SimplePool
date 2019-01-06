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

  def self_call(_module, _call, _context, _options), do: throw "PRI0"
  def self_cast(_module, _call, _context, _options), do: throw "PRI0"

  def internal_system_call(_module, _call, _context, _options), do: throw "PRI0"
  def internal_system_cast(_module, _call, _context, _options), do: throw "PRI0"

  def internal_call(_module, _call, _context, _options), do: throw "PRI0"
  def internal_cast(_module, _call, _context, _options), do: throw "PRI0"

  def remote_system_call(_module, _remote_node, _call, _context, _options), do: throw "PRI0"
  def remote_system_cast(_module, _remote_node, _call, _context, _options), do: throw "PRI0"

  def remote_call(_module, _remote_node, _call, _context, _options), do: throw "PRI0"
  def remote_cast(_module, _remote_node, _call, _context, _options), do: throw "PRI0"

  def get_direct_link!(_module, _ref, _context, _options), do: throw "PRI0"
  def s_call_unsafe(_module, _ref, _extended_call, _context, _options, _timeout), do: throw "PRI0"
  def s_cast_unsafe(_module, _ref, _extended_call, _context, _options), do: throw "PRI0"
  def route_call(_module, _envelope, _from, _state), do: throw "PRI0"
  def route_cast(_module, _envelope, _state), do: throw "PRI0"
  def route_info(_module, _envelope, _state), do: throw "PRI0"
  def extended_call(_module, _ref, _timeout, _call, _context), do: throw "PRI0"
  def s_call!(_module, _identifier, _call, _context, _options), do: throw "PRI0"
  def s_call(_module, _identifier, _call, _context, _options), do: throw "PRI0"
  def s_cast!(_module, _identifier, _call, _context, _options), do: throw "PRI0"
  def s_cast(_module, _identifier, _call, _context, _options), do: throw "PRI0"
  def link_forward!(_module, _link, _call, _context, _options), do: throw "PRI0"


end