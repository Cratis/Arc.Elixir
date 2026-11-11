# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Plug do
  @moduledoc """
  The Arc HTTP contract on Plug.

  Add it to a Phoenix endpoint, before the router, or to any Plug pipeline:

      plug Arc.Plug, application: MyApp.Arc

  Requests that are not Arc routes pass through untouched, so the plug can sit in front of the
  rest of your application. It serves:

    * `POST` command routes and `POST <route>/validate`
    * `GET` and `QUERY` query routes, including paging and sorting
    * observable queries as an HTTP snapshot, direct Server-Sent Events and direct WebSocket
    * the multiplexed hubs: WebSocket at `/.cratis/queries/ws` and Server-Sent Events at
      `/.cratis/queries/sse` with its `subscribe` and `unsubscribe` control routes
    * `/.cratis/commands`, `/.cratis/queries`, `/.cratis/me`, `/.cratis/identity-details/schema`,
      `/.cratis/users` and `/.cratis/tenants`

  Routes are derived from module names: `MyApp.Authors.Registration.RegisterAuthor` becomes
  `POST /api/authors/registration/register-author` with the default `segments_to_skip: 1`.

  Use the plug after authentication has run (so `Arc.Authentication` handlers can see the
  caller) and before `Plug.Parsers` is optional - Arc reads the body itself when it is unread.
  """

  @behaviour Plug

  import Plug.Conn

  alias Arc.{CommandResult, Descriptor, QueryResult, Validation}
  alias Arc.Plug.{Introspection, Request}

  @impl true
  def init(opts), do: Keyword.fetch!(opts, :application)

  @impl true
  def call(conn, app) do
    state = Arc.Application.state(app)
    path = conn.request_path

    cond do
      String.starts_with?(path, "/.cratis/") ->
        Introspection.call(conn, app, state)

      command_route?(conn, state) ->
        command(conn, app, Map.fetch!(state.command_routes, path), false)

      validation_route?(conn, state) ->
        command(
          conn,
          app,
          Map.fetch!(state.command_routes, String.replace_suffix(path, "/validate", "")),
          true
        )

      query_route?(conn, state) ->
        query(conn, app, Map.fetch!(state.query_routes, path))

      true ->
        conn
    end
  end

  defp command_route?(conn, state),
    do: conn.method == "POST" and Map.has_key?(state.command_routes, conn.request_path)

  defp validation_route?(conn, state) do
    conn.method == "POST" and String.ends_with?(conn.request_path, "/validate") and
      Map.has_key?(
        state.command_routes,
        String.replace_suffix(conn.request_path, "/validate", "")
      )
  end

  defp query_route?(conn, state),
    do: conn.method in ["GET", "QUERY"] and Map.has_key?(state.query_routes, conn.request_path)

  # Commands

  defp command(conn, app, descriptor, validate_only?) do
    with_context(conn, app, fn conn, ctx ->
      case read_json(conn, app) do
        {:ok, conn, body} when is_map(body) ->
          result =
            Arc.Pipeline.execute_command(descriptor.module, body, ctx,
              validate_only: validate_only?
            )

          respond(conn, CommandResult.status(result), CommandResult.to_wire(result))

        {:ok, conn, _other} ->
          malformed(conn, ctx, "The request body must be a JSON object.")

        {:error, conn, message} ->
          malformed(conn, ctx, message)
      end
    end)
  end

  # Queries

  defp query(conn, app, {descriptor, query}) do
    with_context(conn, app, fn conn, ctx ->
      cond do
        query.observable? and websocket?(conn) ->
          upgrade_direct(conn, %{app: app, descriptor: descriptor, query: query, ctx: ctx})

        query.observable? and event_stream?(conn) ->
          Arc.Plug.Sse.stream(conn, app, descriptor, query, ctx)

        true ->
          case request_options(conn, app) do
            {:ok, conn, args, opts} ->
              result = Arc.Pipeline.execute_query(descriptor, query, args, ctx, opts)

              conn =
                if conn.method == "QUERY",
                  do: put_resp_header(conn, "cache-control", "no-store"),
                  else: conn

              respond(conn, QueryResult.status(result), QueryResult.to_wire(result))

            {:error, conn, message} ->
              result = %QueryResult{
                correlation_id: ctx.correlation_id,
                validation_results: [Validation.error(message, [], reason: "malformedRequest")]
              }

              respond(conn, 400, QueryResult.to_wire(result))
          end
      end
    end)
  end

  @reserved ~w(page pagesize sortby sortdirection waitforfirstresult waitforfirstresulttimeout)

  defp request_options(%{method: "GET"} = conn, _app) do
    params = Plug.Conn.Query.decode(conn.query_string)
    lowered = Map.new(params, fn {k, v} -> {String.downcase(k), v} end)
    args = Map.reject(params, fn {k, _} -> String.downcase(k) in @reserved end)

    with {:ok, page} <- non_negative(lowered["page"]),
         {:ok, size} <- non_negative(lowered["pagesize"]),
         {:ok, direction} <- direction(lowered["sortdirection"]) do
      {:ok, conn, args,
       [page: page, page_size: size, sort_by: lowered["sortby"], sort_direction: direction]}
    else
      :error -> {:error, conn, "The paging or sorting arguments are not valid."}
    end
  end

  defp request_options(conn, app) do
    case read_json(conn, app) do
      {:ok, conn, %{} = body} ->
        args = Map.get(body, "arguments", %{})
        paging = Map.get(body, "paging", %{})
        sorting = Map.get(body, "sorting", %{})

        with true <- query_body_maps?(args, paging, sorting),
             {:ok, page} <- non_negative(paging["page"]),
             {:ok, size} <- non_negative(paging["pageSize"]),
             {:ok, direction} <- direction(sorting["direction"]) do
          {:ok, conn, args,
           [page: page, page_size: size, sort_by: sorting["field"], sort_direction: direction]}
        else
          _ -> {:error, conn, "The QUERY body is not valid."}
        end

      {:ok, conn, _} ->
        {:error, conn, "The request body must be a JSON object."}

      {:error, conn, message} ->
        {:error, conn, message}
    end
  end

  defp query_body_maps?(args, paging, sorting),
    do: is_map(args) and is_map(paging) and is_map(sorting)

  defp non_negative(nil), do: {:ok, nil}
  defp non_negative(v) when is_integer(v) and v >= 0, do: {:ok, v}

  defp non_negative(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, ""} when i >= 0 -> {:ok, i}
      _ -> :error
    end
  end

  defp non_negative(_), do: :error

  defp direction(nil), do: {:ok, :asc}

  defp direction(v) when is_binary(v) do
    case String.downcase(v) do
      d when d in ["asc", "ascending"] -> {:ok, :asc}
      d when d in ["desc", "descending"] -> {:ok, :desc}
      _ -> :error
    end
  end

  defp direction(_), do: :error

  # Helpers

  defp with_context(conn, app, fun) do
    case Request.build(conn, app) do
      {:ok, conn, ctx} -> fun.(conn, ctx)
      {:unauthenticated, conn} -> respond(conn, 401, %{"message" => "Authentication failed."})
    end
  end

  @doc false
  def read_json(conn, app) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} -> read_body_json(conn, app)
      %{"_json" => json} -> {:ok, conn, json}
      params -> {:ok, conn, params}
    end
  end

  defp read_body_json(conn, app) do
    limit = Arc.Application.state(app).config[:max_body_bytes]

    case read_body(conn, length: limit) do
      {:ok, "", conn} ->
        {:error, conn, "The request body is empty."}

      {:ok, body, conn} ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, conn, decoded}
          {:error, _} -> {:error, conn, "The request body is not valid JSON."}
        end

      {:more, _, conn} ->
        {:error, conn, "The request body is too large."}

      {:error, _} ->
        {:error, conn, "The request body could not be read."}
    end
  end

  defp malformed(conn, ctx, message) do
    result = %CommandResult{
      correlation_id: ctx.correlation_id,
      validation_results: [Validation.error(message, [], reason: "malformedRequest")]
    }

    respond(conn, 400, CommandResult.to_wire(result))
  end

  @doc false
  def respond(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  defp websocket?(conn),
    do: get_req_header(conn, "upgrade") |> Enum.any?(&(String.downcase(&1) == "websocket"))

  defp event_stream?(conn),
    do: get_req_header(conn, "accept") |> Enum.any?(&String.contains?(&1, "text/event-stream"))

  defp upgrade_direct(conn, socket_state) do
    conn
    |> WebSockAdapter.upgrade(Arc.Plug.DirectSocket, socket_state, [])
    |> halt()
  end

  @doc false
  @spec query_names(module()) :: map()
  def query_names(app), do: Arc.Application.state(app).query_names

  @doc false
  @spec route_of(Descriptor.t()) :: String.t()
  def route_of(descriptor), do: Descriptor.command_route(descriptor)
end
