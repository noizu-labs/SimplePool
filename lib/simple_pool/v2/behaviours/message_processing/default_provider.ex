#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2019 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.SimplePool.V2.MessageProcessing.DefaultProvider do
  require Logger


  def __delegate_call_handler(m, envelope = {_, _call, context}, from, %Noizu.SimplePool.Worker.State{initialized: :delayed_init} = state) do
    __delegate_call_handler(m, envelope, from, m.delayed_init(state, context))
  end
  def __delegate_call_handler(m, envelope = {_, _call, context}, from, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case m.pool_worker_state_entity().load(state.worker_ref, context, %{}) do
      nil -> {:reply, :error, state}
      inner_state -> __delegate_call_handler(m, envelope, from, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
    end
  end
  def __delegate_call_handler(m, envelope, from, state) do
    if m.meta()[:inactivity_check] do
      l = :os.system_time(:seconds)
      case state.inner_state.__struct__.__call_handler(envelope, from, state.inner_state) do
        {:reply, response, inner_state} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:reply, response, inner_state, hibernate} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}, hibernate}
        {:stop, reason, inner_state} -> {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:stop, reason, response, inner_state} -> {:stop, reason, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:noreply, inner_state} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:noreply, inner_state, hibernate} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}, hibernate}
      end
    else
      case state.inner_state.__struct__.__call_handler(envelope, from, state.inner_state) do
        {:reply, response, inner_state} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:reply, response, inner_state, hibernate} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}, hibernate}
        {:stop, reason, inner_state} -> {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:stop, reason, response, inner_state} -> {:stop, reason, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:noreply, inner_state} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:noreply, inner_state, hibernate} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}, hibernate}
      end
    end
  end

  def __delegate_cast_handler(m, envelope = {_, _call, context}, %Noizu.SimplePool.Worker.State{initialized: :delayed_init} = state) do
    __delegate_cast_handler(m, envelope, m.delayed_init(state, context))
  end
  def __delegate_cast_handler(m, envelope = {_, _call, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case m.pool_worker_state_entity().load(state.worker_ref, context, %{}) do
      nil -> {:noreply, state}
      inner_state -> __delegate_cast_handler(m, envelope, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
    end
  end
  def __delegate_cast_handler(m, envelope, state) do
    if m.meta()[:inactivity_check] do
      l = :os.system_time(:seconds)
      case state.inner_state.__struct__.__cast_handler(envelope, state.inner_state) do
        {:reply, response, inner_state} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:reply, response, inner_state, hibernate} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}, hibernate}
        {:stop, reason, inner_state} -> {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:stop, reason, response, inner_state} -> {:stop, reason, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:noreply, inner_state} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:noreply, inner_state, hibernate} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}, hibernate}
      end
    else
      case state.inner_state.__struct__.__cast_handler(envelope, state.inner_state) do
        {:reply, response, inner_state} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:reply, response, inner_state, hibernate} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}, hibernate}
        {:stop, reason, inner_state} -> {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:stop, reason, response, inner_state} -> {:stop, reason, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:noreply, inner_state} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:noreply, inner_state, hibernate} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}, hibernate}
      end
    end
  end

  def __delegate_info_handler(m, envelope = {_, _call, context}, %Noizu.SimplePool.Worker.State{initialized: :delayed_init} = state) do
    __delegate_info_handler(m, envelope, m.delayed_init(state, context))
  end
  def __delegate_info_handler(m, envelope = {_, _call, context}, %Noizu.SimplePool.Worker.State{initialized: false} = state) do
    case m.pool_worker_state_entity().load(state.worker_ref, context, %{}) do
      nil -> {:noreply, state}
      inner_state -> __delegate_info_handler(m, envelope, %Noizu.SimplePool.Worker.State{state| initialized: true, inner_state: inner_state})
    end
  end
  def __delegate_info_handler(m, envelope, state) do
    if m.meta()[:inactivity_check] do
      l = :os.system_time(:seconds)
      case state.inner_state.__struct__.__info_handler(envelope, state.inner_state) do
        {:reply, response, inner_state} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:reply, response, inner_state, hibernate} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}, hibernate}
        {:stop, reason, inner_state} -> {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:stop, reason, response, inner_state} -> {:stop, reason, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:noreply, inner_state} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}}
        {:noreply, inner_state, hibernate} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state, last_activity: l}, hibernate}
      end
    else
      case state.inner_state.__struct__.__info_handler(envelope, state.inner_state) do
        {:reply, response, inner_state} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:reply, response, inner_state, hibernate} -> {:reply, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}, hibernate}
        {:stop, reason, inner_state} -> {:stop, reason, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:stop, reason, response, inner_state} -> {:stop, reason, response, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:noreply, inner_state} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}}
        {:noreply, inner_state, hibernate} -> {:noreply, %Noizu.SimplePool.Worker.State{state| inner_state: inner_state}, hibernate}
      end
    end
  end
end