#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2018 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.Server.Router.DefaultImplementation do
   @moduledoc """
    Process routing implementation.
    @todo combine with WorkerManagement module (retain strategy pattern).
  """

  def extended_call(module, ref, timeout, call, context) do
    # @TODO @PRI-0
    # if redirect router then: {:s_call!, {__MODULE__, ref, timeout}, {:s, call, context}}
    # else: {:s, call, context}
    {:s_call!, {module, ref, timeout}, {:s, call, context}}
  end

  def self_call(_module, _call, _context, _options), do: throw :pri0_self_call
  def self_cast(_module, _call, _context, _options), do: throw :pri0_self_cast

  def internal_system_call(_module, _call, _context, _options), do: throw :pri0_internal_system_call
  def internal_system_cast(_module, _call, _context, _options), do: throw :pri0_internal_system_cast

  def internal_call(_module, _call, _context, _options), do: throw :pri0_internal_call
  def internal_cast(_module, _call, _context, _options), do: throw :pri0_internal_cast

  def remote_system_call(_module, _remote_node, _call, _context, _options), do: throw :pri0_remote_system_call
  def remote_system_cast(_module, _remote_node, _call, _context, _options), do: throw :pri0_remote_system_cast

  def remote_call(_module, _remote_node, _call, _context, _options), do: throw :pri0_remote_call
  def remote_cast(_module, _remote_node, _call, _context, _options), do: throw :pri0_remote_cast

  def get_direct_link!(_module, _ref, _context, _options), do: throw :pri0_get_direct_link!
  def s_call_unsafe(_module, _ref, _extended_call, _context, _options, _timeout), do: throw :pri0_s_call_unsafe
  def s_cast_unsafe(_module, _ref, _extended_call, _context, _options), do: throw :pri0_s_cast_unsafe
  def route_call(_module, _envelope, _from, _state), do: throw :pri0_route_call
  def route_cast(_module, _envelope, _state), do: throw :pri0_route_cast
  def route_info(_module, _envelope, _state), do: throw :pri0_route_info

  def s_call!(_module, _identifier, _call, _context, _options), do: throw :pri0_s_call!
  def s_call(_module, _identifier, _call, _context, _options), do: throw :pri0_s_call
  def s_cast!(_module, _identifier, _call, _context, _options), do: throw :pri0_s_cast!
  def s_cast(_module, _identifier, _call, _context, _options), do: throw :pri0_s_cast
  def link_forward!(_module, _link, _call, _context, _options), do: throw :pri0_link_forward!


end