# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Plug.Hub do
  @moduledoc """
  The multiplexed WebSocket hub at `/.cratis/queries/ws`.

  One connection carries many observable-query subscriptions. Messages share an envelope with a
  PascalCase `type` (`Subscribe`, `Unsubscribe`, `QueryResult`, `Unauthorized`, `Error`, `Ping`,
  `Pong`, `Connected`), a client-assigned `queryId`, an optional `revision` and a `payload`.

  A connection opens with `Connected`, whose payload is the server-assigned connection id. Each
  subscription is authorized independently by the ordinary query pipeline: a denied
  subscription ends with `Unauthorized` for its `queryId` without disturbing the others.

  Revisions order operations for one `queryId`: a stale message is ignored, a duplicate is
  idempotent, and an unsubscribe is remembered so a delayed subscribe cannot resurrect it.

  Each subscription's `transferMode` shapes its emissions (see `Arc.Plug.HubSession`): `full` sends
  snapshots, `delta` a snapshot and then change sets, anything else both on every emission.
  The same protocol is served over Server-Sent Events by `Arc.Plug.SseHub`.
  """

  @behaviour WebSock

  alias Arc.Plug.HubSession
  alias Arc.QueryResult

  @impl true
  def init(%{app: app, ctx: ctx}) do
    id = Arc.Context.new_correlation_id()
    {:push, {:text, HubSession.connected(id)}, HubSession.new(app, ctx)}
  end

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, %{} = msg} -> reply(HubSession.handle(state, msg))
      _ -> {:ok, state}
    end
  end

  def handle_in(_other, state), do: {:ok, state}

  @impl true
  def handle_info({:arc_query_result, query_id, %QueryResult{} = result}, state),
    do: reply(HubSession.result(state, query_id, result))

  def handle_info(_other, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state), do: HubSession.terminate(state)

  defp reply({[], state}), do: {:ok, state}
  defp reply({messages, state}), do: {:push, Enum.map(messages, &{:text, &1}), state}
end
