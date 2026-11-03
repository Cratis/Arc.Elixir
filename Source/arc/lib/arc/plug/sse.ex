# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Plug.Sse do
  @moduledoc false

  # Direct Server-Sent Events for one observable query. Each emission is written as exactly
  # `data: {query result envelope}\n\n`, with no event name and no id.

  import Plug.Conn

  alias Arc.{QueryResult, Subscription}

  def stream(conn, app, descriptor, query, ctx) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    {:ok, args, opts} = options(conn)

    spec = %{
      owner: self(),
      id: :sse,
      descriptor: descriptor,
      query: query,
      args: args,
      ctx: ctx,
      opts: opts
    }

    case Subscription.start(app, spec) do
      {:ok, subscription} ->
        loop(conn, subscription)

      {:error, _} ->
        conn
    end
  end

  defp options(conn) do
    params = Plug.Conn.Query.decode(conn.query_string)
    lowered = Map.new(params, fn {k, v} -> {String.downcase(k), v} end)

    args =
      Map.reject(params, fn {k, _} ->
        String.downcase(k) in ~w(page pagesize sortby sortdirection)
      end)

    opts = [
      page: to_int(lowered["page"]),
      page_size: to_int(lowered["pagesize"]),
      sort_by: lowered["sortby"],
      sort_direction:
        if(String.downcase(lowered["sortdirection"] || "") in ["desc", "descending"],
          do: :desc,
          else: :asc
        )
    ]

    {:ok, args, opts}
  end

  defp to_int(nil), do: nil

  defp to_int(v) do
    case Integer.parse(v) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp loop(conn, subscription) do
    receive do
      {:arc_query_result, _id, %QueryResult{} = result} ->
        case chunk(conn, "data: " <> Jason.encode!(QueryResult.to_wire(result)) <> "\n\n") do
          {:ok, conn} -> loop(conn, subscription)
          {:error, _closed} -> stop(conn, subscription)
        end
    after
      15_000 ->
        # An SSE comment, not an emission: it detects a closed connection while the query is idle.
        case chunk(conn, ": keep-alive\n\n") do
          {:ok, conn} -> loop(conn, subscription)
          {:error, _closed} -> stop(conn, subscription)
        end
    end
  end

  defp stop(conn, subscription) do
    Subscription.stop(subscription)
    conn
  end
end
