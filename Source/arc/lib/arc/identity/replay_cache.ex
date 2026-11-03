# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Identity.ReplayCache do
  @moduledoc false

  # Process-local replay memory for signed forwarded identity envelopes and on-behalf assertions,
  # one per Arc application, started with it. Like Arc on .NET it is not shared across nodes or
  # restarts: a captured credential can be replayed once to each other node within its lifetime.

  use GenServer

  require Logger

  @capacity 100_000
  @purge_every 1024

  def child_spec(app), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [app]}}

  def start_link(app), do: GenServer.start_link(__MODULE__, app, name: name(app))

  def name(app), do: Module.concat(app, ReplayCache)

  @doc "Reserves a signed envelope's `{audience, key id, nonce}` until `expires`. `false` when seen or full."
  @spec reserve_forwarded(module(), term(), integer(), integer()) :: boolean()
  def reserve_forwarded(app, key, expires, now), do: call(app, {:forwarded, key, expires, now})

  @doc "Records an on-behalf token id until `keep_until`. `false` when already recorded and still live."
  @spec record_on_behalf(module(), String.t(), integer(), integer()) :: boolean()
  def record_on_behalf(app, token_id, keep_until, now),
    do: call(app, {:on_behalf, token_id, keep_until, now})

  defp call(app, message) do
    case GenServer.whereis(name(app)) do
      nil ->
        # Fail closed: without replay memory a replayed credential could not be refused.
        Logger.error(
          "#{inspect(app)} is not started, so signed forwarded identity cannot check for replays and is rejected. Add it to your supervision tree."
        )

        false

      pid ->
        GenServer.call(pid, message)
    end
  end

  @impl true
  def init(_app), do: {:ok, %{forwarded: %{}, order: :gb_sets.new(), on_behalf: %{}, calls: 0}}

  @impl true
  def handle_call({:forwarded, key, expires, now}, _from, state) do
    state = purge_forwarded(state, now)

    if map_size(state.forwarded) >= @capacity or Map.has_key?(state.forwarded, key) do
      {:reply, false, state}
    else
      {:reply, true,
       %{
         state
         | forwarded: Map.put(state.forwarded, key, expires),
           order: :gb_sets.add({expires, key}, state.order)
       }}
    end
  end

  def handle_call({:on_behalf, token_id, keep_until, now}, _from, state) do
    state = maybe_purge_on_behalf(state, now)

    case Map.get(state.on_behalf, token_id) do
      until when is_integer(until) and until > now ->
        {:reply, false, state}

      _ ->
        {:reply, true, %{state | on_behalf: Map.put(state.on_behalf, token_id, keep_until)}}
    end
  end

  # Entries are kept through their expiry second inclusive.
  defp purge_forwarded(state, now) do
    case :gb_sets.is_empty(state.order) do
      true ->
        state

      false ->
        {{expires, key} = smallest, rest} = :gb_sets.take_smallest(state.order)

        if expires < now do
          purge_forwarded(
            %{state | forwarded: Map.delete(state.forwarded, key), order: rest},
            now
          )
        else
          _ = smallest
          state
        end
    end
  end

  defp maybe_purge_on_behalf(%{calls: calls} = state, now) do
    state = %{state | calls: calls + 1}

    if rem(state.calls, @purge_every) == 0,
      do: %{state | on_behalf: Map.reject(state.on_behalf, fn {_id, until} -> until <= now end)},
      else: state
  end
end
