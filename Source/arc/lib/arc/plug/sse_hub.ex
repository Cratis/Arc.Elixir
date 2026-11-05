# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Plug.SseHub do
  @moduledoc """
  The multiplexed Server-Sent Events hub at `/.cratis/queries/sse`.

  It carries the same protocol as the WebSocket hub (`Arc.Plug.Hub`), for clients that cannot or
  do not want a WebSocket. A browser `EventSource` can only receive, so the two directions use
  two requests:

    * `GET /.cratis/queries/sse` opens the stream. It starts with a `Connected` message whose
      `payload` is the connection id, and carries every `QueryResult`, `Unauthorized`, `Error` and
      keep-alive `Ping` message as a `data:` event.
    * `POST /.cratis/queries/sse/subscribe` with `{connectionId, queryId, revision, request}` adds
      or revision-replaces a subscription on the stream.
    * `POST /.cratis/queries/sse/unsubscribe` with `{connectionId, queryId, revision}` cancels one.

  Closing the stream ends every subscription it owns. A control request for an unknown connection,
  or from a caller other than the one that opened the stream, is answered `404` (the same status
  for both, so a connection id is never confirmed to someone else). The caller is compared on the
  principal id and whether it is authenticated; the tenant is not compared, and each subscription
  runs with the context of the POST that created it, so a client that sets the tenant header on
  its control requests subscribes in that tenant. A connection opened by an anonymous caller has
  no identity to bind to.
  """

  import Plug.Conn

  alias Arc.Plug.HubSession
  alias Arc.QueryResult

  @control_timeout 5_000

  @doc false
  @spec registry(module()) :: atom()
  def registry(app), do: Module.concat(app, Connections)

  @doc false
  # Opens the stream in the calling process, which lives as long as the connection.
  def stream(conn, app, ctx) do
    id = Arc.Context.new_correlation_id()
    owner = %{principal_id: ctx.principal.id, authenticated?: ctx.principal.authenticated?}

    case Registry.register(registry(app), id, owner) do
      {:ok, _} ->
        conn =
          conn
          |> put_resp_content_type("text/event-stream")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_header("x-accel-buffering", "no")
          |> send_chunked(200)

        session = HubSession.new(app, ctx)

        case write(conn, [HubSession.connected(id)]) do
          {:ok, conn} -> loop(conn, session)
          {:error, _closed} -> conn
        end

      {:error, _already} ->
        send_resp(conn, 500, "")
    end
  end

  @doc false
  # Answers `POST .../subscribe` and `POST .../unsubscribe`.
  def control(conn, app, ctx, kind, body) do
    with {:ok, connection_id, query_id} <- ids(body),
         true <- kind == :unsubscribe or is_map(body["request"]),
         true <- is_nil(body["revision"]) or is_integer(body["revision"]) do
      case lookup(app, connection_id, ctx) do
        nil ->
          send_status(conn, 404)

        pid ->
          ref = make_ref()

          send(
            pid,
            {:arc_hub_control, self(), ref, kind, Map.put(body, "queryId", query_id), ctx}
          )

          receive do
            {^ref, :ok} -> send_status(conn, 200)
            {^ref, :bad_request} -> send_status(conn, 400)
          after
            @control_timeout -> send_status(conn, 503)
          end
      end
    else
      _ -> send_status(conn, 400)
    end
  end

  defp ids(%{"connectionId" => connection, "queryId" => query})
       when is_binary(connection) and is_binary(query) and connection != "" and query != "",
       do: {:ok, connection, query}

  defp ids(_), do: :error

  defp lookup(app, connection_id, ctx) do
    case Registry.lookup(registry(app), connection_id) do
      [{pid, owner}] -> if same_caller?(owner, ctx.principal), do: pid
      _ -> nil
    end
  end

  defp same_caller?(owner, principal),
    do: owner.principal_id == principal.id and owner.authenticated? == principal.authenticated?

  defp send_status(conn, status), do: conn |> send_resp(status, "") |> halt()

  defp loop(conn, session) do
    receive do
      {:arc_query_result, query_id, %QueryResult{} = result} ->
        {messages, session} = HubSession.result(session, query_id, result)
        continue(conn, session, messages)

      {:arc_hub_control, from, ref, kind, body, ctx} ->
        {status, messages, session} = control_message(session, kind, body, ctx)
        send(from, {ref, status})
        continue(conn, session, messages)
    after
      HubSession.keep_alive_ms() ->
        # A message at least every interval is the promise of the `Connected` message, and
        # writing it is also how a closed connection is noticed while every query is idle.
        continue(conn, session, [HubSession.ping()])
    end
  end

  defp control_message(session, :subscribe, body, ctx),
    do: HubSession.subscribe(session, body, ctx)

  defp control_message(session, :unsubscribe, body, _ctx) do
    {status, session} = HubSession.unsubscribe(session, body)
    {status, [], session}
  end

  defp continue(conn, session, messages) do
    case write(conn, messages) do
      {:ok, conn} ->
        loop(conn, session)

      {:error, _closed} ->
        HubSession.terminate(session)
        conn
    end
  end

  defp write(conn, messages) do
    Enum.reduce_while(messages, {:ok, conn}, fn message, {:ok, conn} ->
      case chunk(conn, "data: " <> message <> "\n\n") do
        {:ok, conn} -> {:cont, {:ok, conn}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
