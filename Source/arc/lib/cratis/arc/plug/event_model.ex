# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Plug.EventModel do
  @moduledoc false

  # The `/.cratis/event-model` explorer and its API: the same routes as the C# explorer.

  import Plug.Conn

  alias Cratis.Arc.Plug.Request

  @prefix "/.cratis/event-model"

  def prefix, do: @prefix

  def call(conn, app, state, path) do
    if enabled?(state.config) do
      serve(conn, app, state, String.replace_prefix(path, @prefix, ""))
    else
      conn
    end
  end

  # `:auto` serves under Mix (development) and not from a release; the explorer shows the whole model.
  defp enabled?(config) do
    case {config[:introspection], Keyword.get(config, :event_model, :auto)} do
      {false, _} ->
        false

      {_, :auto} ->
        Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :dev

      {_, value} ->
        value == true
    end
  end

  defp serve(conn, app, state, rest) do
    case Request.build(conn, app) do
      {:unauthenticated, conn} ->
        text(conn, 401, "Authentication failed.")

      {:ok, conn, ctx} ->
        if state.config[:introspection] == :authenticated and not ctx.principal.authenticated? do
          text(conn, 401, "Authentication is required.")
        else
          conn |> put_resp_header("cache-control", "no-store") |> route(state, rest)
        end
    end
  end

  # The explorer's assets are relative to the document, so it is served from a path with a slash.
  defp route(conn, _state, "") do
    conn |> put_resp_header("location", conn.request_path <> "/") |> send_resp(301, "") |> halt()
  end

  defp route(conn, _state, "/"), do: asset(conn, "index.html")

  defp route(conn, state, "/hierarchy"),
    do: json(conn, 200, Cratis.Arc.EventModel.hierarchy(apps(state)))

  defp route(conn, state, "/documents/" <> rest) do
    with [project, document, part] when part in ["source", "model"] <- String.split(rest, "/"),
         {:ok, content} <-
           Cratis.Arc.EventModel.document(
             apps(state),
             decode(project),
             decode(document),
             kind(part)
           ) do
      if part == "model",
        do:
          conn |> put_resp_content_type("application/json") |> send_resp(200, content) |> halt(),
        else: conn |> put_resp_content_type("text/plain") |> send_resp(200, content) |> halt()
    else
      _ -> text(conn, 404, "Not found.")
    end
  end

  defp route(conn, _state, "/assets/" <> path), do: asset(conn, Path.join("assets", path))
  defp route(conn, _state, _other), do: text(conn, 404, "Not found.")

  defp kind("model"), do: :model
  defp kind("source"), do: :source
  defp decode(segment), do: URI.decode(segment)

  defp apps(state) do
    own = Keyword.fetch!(state.config, :otp_app)
    config = state.config |> Keyword.get(:event_model_apps, [])
    Enum.uniq([own | config])
  end

  # Only files inside the packaged explorer can be read; nothing a request states reaches anywhere else.
  defp asset(conn, relative) do
    root = Path.join(:code.priv_dir(:cratis_arc), "event_model")
    path = Path.expand(Path.join(root, relative))

    cond do
      String.contains?(relative, "..") or not String.starts_with?(path, root <> "/") ->
        text(conn, 404, "Not found.")

      File.regular?(path) ->
        conn
        |> put_resp_content_type(MIME.from_path(path))
        |> send_file(200, path)
        |> halt()

      relative == "index.html" ->
        text(
          conn,
          404,
          "The explorer is not built into this package. Run `yarn build` in Source/event_model_viewer."
        )

      true ->
        text(conn, 404, "Not found.")
    end
  end

  defp json(conn, status, body),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(body))
      |> halt()

  defp text(conn, status, body),
    do: conn |> put_resp_content_type("text/plain") |> send_resp(status, body) |> halt()
end
