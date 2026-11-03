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

  Transfer mode `delta` is served as full snapshots; the change set is not computed.
  """

  @behaviour WebSock

  alias Arc.{QueryResult, Subscription}

  @keep_alive_ms 10_000
  @max_revision 9_007_199_254_740_991

  @impl true
  def init(%{app: app, ctx: ctx}) do
    state = %{app: app, ctx: ctx, subscriptions: %{}, revisions: %{}}
    id = Arc.Context.new_correlation_id()

    {:push,
     {:text,
      message("Connected", %{
        "payload" => id,
        "keepAliveIntervalMs" => @keep_alive_ms,
        "supportsSubscriptionRevisions" => true
      })}, state}
  end

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, %{"type" => "Subscribe"} = msg} ->
        subscribe(msg, state)

      {:ok, %{"type" => "Unsubscribe"} = msg} ->
        unsubscribe(msg, state)

      {:ok, %{"type" => "Ping"}} ->
        {:push, {:text, message("Pong", %{"timestamp" => now()})}, state}

      _ ->
        {:ok, state}
    end
  end

  def handle_in(_other, state), do: {:ok, state}

  @impl true
  def handle_info({:arc_query_result, query_id, %QueryResult{} = result}, state) do
    revision = get_in(state.subscriptions, [query_id, :revision])

    cond do
      not Map.has_key?(state.subscriptions, query_id) ->
        {:ok, state}

      result.authorized? == false ->
        {:push,
         {:text, message("Unauthorized", with_revision(%{"queryId" => query_id}, revision))},
         drop(state, query_id)}

      true ->
        body =
          with_revision(
            %{"queryId" => query_id, "payload" => QueryResult.to_wire(result)},
            revision
          )

        {:push, {:text, message("QueryResult", body)}, state}
    end
  end

  def handle_info(_other, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    for {_id, %{pid: pid}} <- state.subscriptions, do: Subscription.stop(pid)
    :ok
  end

  defp subscribe(%{"queryId" => query_id, "payload" => request} = msg, state)
       when is_binary(query_id) and is_map(request) do
    revision = msg["revision"]

    cond do
      not valid_revision?(revision) ->
        error(query_id, "The revision is not valid.", state)

      stale?(state, query_id, revision) ->
        {:ok, state}

      true ->
        state = stop_existing(state, query_id)
        start_subscription(query_id, revision, request, state)
    end
  end

  defp subscribe(_msg, state),
    do:
      {:push, {:text, message("Error", %{"payload" => "The Subscribe message is not valid."})},
       state}

  defp start_subscription(query_id, revision, request, state) do
    case Map.fetch(Arc.Application.state(state.app).query_names, request["queryName"]) do
      :error ->
        error(query_id, "Unknown query '#{request["queryName"]}'.", state)

      {:ok, {descriptor, query}} ->
        arguments = request["arguments"] || %{}

        opts = [
          page: request["page"],
          page_size: request["pageSize"],
          sort_by: request["sortBy"],
          sort_direction:
            if(String.downcase(to_string(request["sortDirection"])) in ["desc", "descending"],
              do: :desc,
              else: :asc
            )
        ]

        spec = %{
          owner: self(),
          id: query_id,
          descriptor: descriptor,
          query: query,
          args: arguments,
          ctx: state.ctx,
          opts: opts
        }

        case Subscription.start(state.app, spec) do
          {:ok, pid} ->
            {:ok,
             put_in(state.subscriptions[query_id], %{pid: pid, revision: revision})
             |> remember(query_id, revision)}

          {:error, reason} ->
            error(
              query_id,
              "The subscription could not be started: #{inspect(reason)}. Is the Arc application started?",
              state
            )
        end
    end
  end

  defp unsubscribe(%{"queryId" => query_id} = msg, state) do
    revision = msg["revision"]

    if stale?(state, query_id, revision) do
      {:ok, state}
    else
      {:ok, state |> stop_existing(query_id) |> remember(query_id, revision)}
    end
  end

  defp unsubscribe(_msg, state), do: {:ok, state}

  defp stop_existing(state, query_id) do
    case Map.pop(state.subscriptions, query_id) do
      {nil, _} ->
        state

      {%{pid: pid}, rest} ->
        Subscription.stop(pid)
        %{state | subscriptions: rest}
    end
  end

  defp drop(state, query_id), do: stop_existing(state, query_id)

  defp remember(state, _id, nil), do: state
  defp remember(state, id, revision), do: put_in(state.revisions[id], revision)

  defp stale?(_state, _id, nil), do: false
  defp stale?(state, id, revision), do: revision < Map.get(state.revisions, id, 0)

  defp valid_revision?(nil), do: true
  defp valid_revision?(r), do: is_integer(r) and r > 0 and r <= @max_revision

  defp error(query_id, text, state),
    do: {:push, {:text, message("Error", %{"queryId" => query_id, "payload" => text})}, state}

  defp with_revision(map, nil), do: map
  defp with_revision(map, revision), do: Map.put(map, "revision", revision)

  defp message(type, extra), do: Jason.encode!(Map.put(extra, "type", type))
  defp now, do: System.os_time(:millisecond)
end
