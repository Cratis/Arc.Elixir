# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Plug.HubSession do
  @moduledoc false
  # The protocol of the multiplexed hubs, independent of the transport.
  #
  # One session is one hub connection: a WebSocket (`Arc.Plug.Hub`) or a Server-Sent Events stream
  # (`Arc.Plug.SseHub`). It owns the subscriptions of the connection, orders their operations by
  # revision, authorizes each one through the ordinary query pipeline and shapes every emission
  # according to the subscription's transfer mode. Functions return the messages to write as
  # encoded JSON strings, so a transport only moves bytes.
  #
  # The subscriptions send `{:arc_query_result, query_id, result}` to the process that started
  # them; the transport forwards that to `result/3`.

  alias Arc.{QueryResult, Subscription}

  @keep_alive_ms 10_000
  @max_revision 9_007_199_254_740_991

  @type t :: %{
          app: module(),
          ctx: Arc.Context.t(),
          subscriptions: map(),
          revisions: map()
        }

  @doc "The keep-alive cadence the hub advertises, in milliseconds."
  @spec keep_alive_ms() :: pos_integer()
  def keep_alive_ms, do: @keep_alive_ms

  @doc "Starts a session for an application and the context of the connection."
  @spec new(module(), Arc.Context.t()) :: t()
  def new(app, ctx), do: %{app: app, ctx: ctx, subscriptions: %{}, revisions: %{}}

  @doc "The `Connected` message that opens a connection."
  @spec connected(String.t()) :: String.t()
  def connected(id) do
    message("Connected", %{
      "payload" => id,
      "keepAliveIntervalMs" => @keep_alive_ms,
      "supportsSubscriptionRevisions" => true
    })
  end

  @doc "A `Ping` keep-alive message."
  @spec ping() :: String.t()
  def ping, do: message("Ping", %{"timestamp" => now()})

  @doc "Handles a decoded client message of a WebSocket connection."
  @spec handle(t(), term()) :: {[String.t()], t()}
  def handle(state, %{"type" => "Subscribe"} = msg) do
    {_status, out, state} = subscribe(state, msg, state.ctx)
    {out, state}
  end

  def handle(state, %{"type" => "Unsubscribe"} = msg) do
    {_status, state} = unsubscribe(state, msg)
    {[], state}
  end

  def handle(state, %{"type" => "Ping"}), do: {[message("Pong", %{"timestamp" => now()})], state}
  def handle(state, _other), do: {[], state}

  @doc """
  Adds or revision-replaces a subscription for `ctx`.

  Returns `{status, messages, state}` where `status` is `:ok` or `:bad_request`: the SSE control
  endpoint answers it, the WebSocket ignores it and sends the messages.
  """
  @spec subscribe(t(), map(), Arc.Context.t()) :: {:ok | :bad_request, [String.t()], t()}
  def subscribe(state, %{"queryId" => query_id} = msg, ctx) when is_binary(query_id) do
    request = request_of(msg)
    revision = msg["revision"]

    cond do
      query_id == "" or not is_map(request) ->
        {:bad_request, [message("Error", %{"payload" => "The Subscribe message is not valid."})],
         state}

      not valid_revision?(revision) ->
        {:bad_request, [error(query_id, "The revision is not valid.")], state}

      stale?(state, query_id, revision) ->
        {:ok, [], state}

      true ->
        state = stop_existing(state, query_id)
        {out, state} = start_subscription(state, query_id, revision, request, ctx)
        {:ok, out, state}
    end
  end

  def subscribe(state, _msg, _ctx),
    do:
      {:bad_request, [message("Error", %{"payload" => "The Subscribe message is not valid."})],
       state}

  @doc "Cancels a subscription, or remembers its revision so a delayed subscribe cannot resurrect it."
  @spec unsubscribe(t(), map()) :: {:ok | :bad_request, t()}
  def unsubscribe(state, %{"queryId" => query_id} = msg) when is_binary(query_id) do
    revision = msg["revision"]

    cond do
      not valid_revision?(revision) ->
        {:bad_request, state}

      stale?(state, query_id, revision) ->
        {:ok, state}

      true ->
        {:ok, state |> stop_existing(query_id) |> remember(query_id, revision)}
    end
  end

  def unsubscribe(state, _msg), do: {:bad_request, state}

  @doc "Shapes an emission of a subscription into messages."
  @spec result(t(), String.t(), QueryResult.t()) :: {[String.t()], t()}
  def result(state, query_id, %QueryResult{} = result) do
    case Map.fetch(state.subscriptions, query_id) do
      :error ->
        {[], state}

      {:ok, subscription} ->
        if result.authorized? == false do
          {[
             message(
               "Unauthorized",
               with_revision(%{"queryId" => query_id}, subscription.revision)
             )
           ], stop_existing(state, query_id)}
        else
          {payload, subscription} = shape(result, subscription)

          body =
            with_revision(%{"queryId" => query_id, "payload" => payload}, subscription.revision)

          {[message("QueryResult", body)], put_in(state.subscriptions[query_id], subscription)}
        end
    end
  end

  @doc "Stops every subscription of the session."
  @spec terminate(t()) :: :ok
  def terminate(state) do
    for {_id, %{pid: pid}} <- state.subscriptions, do: Subscription.stop(pid)
    :ok
  end

  # The wire body is either the subscribe request itself (a WebSocket) or nested under `request`
  # (the SSE control POST).
  defp request_of(%{"payload" => payload}) when is_map(payload), do: payload
  defp request_of(%{"request" => request}) when is_map(request), do: request
  defp request_of(_), do: nil

  defp start_subscription(state, query_id, revision, request, ctx) do
    case Map.fetch(Arc.Application.state(state.app).query_names, request["queryName"]) do
      :error ->
        {[error(query_id, "Unknown query '#{request["queryName"]}'.")], state}

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
          ctx: ctx,
          opts: opts
        }

        case Subscription.start(state.app, spec) do
          {:ok, pid} ->
            subscription = %{
              pid: pid,
              revision: revision,
              mode: mode(request["transferMode"]),
              ordered?: ordered?(opts),
              previous: nil
            }

            {[],
             put_in(state.subscriptions[query_id], subscription) |> remember(query_id, revision)}

          {:error, reason} ->
            {[
               error(
                 query_id,
                 "The subscription could not be started: #{inspect(reason)}. Is the Arc application started?"
               )
             ], state}
        end
    end
  end

  # `full` and `delta` are matched case-insensitively; anything else is served like no preference.
  defp mode(value) when is_binary(value) do
    case String.downcase(value) do
      "full" -> :full
      "delta" -> :delta
      _ -> :default
    end
  end

  defp mode(_), do: :default

  defp ordered?(opts), do: opts[:sort_by] not in [nil, ""] or opts[:page_size] not in [nil, 0]

  # Full mode sends snapshots. Delta mode sends a snapshot first and then only the change set,
  # except for ordered or paged queries, where a position matters and the snapshot goes too.
  # Without a preference every emission carries the snapshot and the change set.
  defp shape(result, subscription) do
    wire = QueryResult.to_wire(result)

    case {QueryResult.success?(result), wire["data"]} do
      {true, items} when is_list(items) and subscription.mode != :full ->
        first? = subscription.previous == nil
        change_set = change_set(subscription.previous, items)
        subscription = %{subscription | previous: items}

        wire =
          cond do
            subscription.mode == :delta and first? ->
              wire

            subscription.mode == :delta and subscription.ordered? ->
              wire

            subscription.mode == :delta and change_set.identity? ->
              wire |> Map.delete("data") |> Map.put("changeSet", change_set.wire)

            true ->
              Map.put(wire, "changeSet", change_set.wire)
          end

        {wire, subscription}

      _ ->
        {wire, subscription}
    end
  end

  defp change_set(previous, current) do
    identity? = Enum.all?(current ++ (previous || []), &has_id?/1)

    cond do
      previous == nil ->
        %{identity?: identity?, wire: wire_set(current, [], [])}

      identity? ->
        before = Map.new(previous, &{id_of(&1), &1})
        now = Map.new(current, &{id_of(&1), &1})

        added = for item <- current, not Map.has_key?(before, id_of(item)), do: item

        replaced =
          for item <- current,
              Map.has_key?(before, id_of(item)),
              Map.fetch!(before, id_of(item)) != item,
              do: item

        removed = for item <- previous, not Map.has_key?(now, id_of(item)), do: item
        %{identity?: true, wire: wire_set(added, replaced, removed)}

      true ->
        added = current -- previous
        removed = previous -- current
        %{identity?: false, wire: wire_set(added, [], removed)}
    end
  end

  defp wire_set(added, replaced, removed),
    do: %{"added" => added, "replaced" => replaced, "removed" => removed}

  defp has_id?(item) when is_map(item), do: id_key(item) != nil
  defp has_id?(_), do: false

  defp id_of(item), do: Map.fetch!(item, id_key(item))

  defp id_key(item), do: Enum.find(Map.keys(item), &(String.downcase(to_string(&1)) == "id"))

  defp stop_existing(state, query_id) do
    case Map.pop(state.subscriptions, query_id) do
      {nil, _} ->
        state

      {%{pid: pid}, rest} ->
        Subscription.stop(pid)
        %{state | subscriptions: rest}
    end
  end

  defp remember(state, _id, nil), do: state
  defp remember(state, id, revision), do: put_in(state.revisions[id], revision)

  defp stale?(_state, _id, nil), do: false
  defp stale?(state, id, revision), do: revision < Map.get(state.revisions, id, 0)

  defp valid_revision?(nil), do: true
  defp valid_revision?(r), do: is_integer(r) and r > 0 and r <= @max_revision

  defp error(query_id, text),
    do: message("Error", %{"queryId" => query_id, "payload" => text})

  defp with_revision(map, nil), do: map
  defp with_revision(map, revision), do: Map.put(map, "revision", revision)

  defp message(type, extra), do: Jason.encode!(Map.put(extra, "type", type))
  defp now, do: System.os_time(:millisecond)
end
