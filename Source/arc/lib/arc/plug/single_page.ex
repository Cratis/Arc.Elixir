# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Plug.SinglePage do
  @moduledoc """
  Serves a single-page application: static files from a directory, and the `index.html` for
  every other `GET` that accepts HTML, so client-side routes survive a refresh.

      plug Arc.Plug, application: MyApp.Arc
      plug Arc.Plug.SinglePage, root: "priv/static/app"

  Place it after `Arc.Plug` so API routes are answered first. Paths under `/api/` and
  `/.cratis/` are never served as the SPA.

  ## Options

    * `:root` - (required) the directory holding the built frontend, relative to the working
      directory or absolute
    * `:index` - the index document; default `"index.html"`
    * `:api_prefixes` - path prefixes that must 404 instead of falling back; default `["/api/", "/.cratis/"]`
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts) do
    %{
      root: Keyword.fetch!(opts, :root),
      index: Keyword.get(opts, :index, "index.html"),
      api_prefixes: Keyword.get(opts, :api_prefixes, ["/api/", "/.cratis/"])
    }
  end

  @impl true
  def call(%{method: method} = conn, opts) when method in ["GET", "HEAD"] do
    path = conn.request_path

    cond do
      Enum.any?(opts.api_prefixes, &String.starts_with?(path, &1)) -> conn
      file = static_file(opts.root, path) -> send_file_halt(conn, file)
      accepts_html?(conn) -> send_file_halt(conn, Path.join(opts.root, opts.index))
      true -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp static_file(root, path) do
    segments = String.split(path, "/", trim: true)

    if segments == [] or ".." in segments do
      nil
    else
      file = Path.join([root | segments])
      if File.regular?(file), do: file
    end
  end

  defp send_file_halt(conn, file) do
    if File.regular?(file) do
      conn
      |> put_resp_content_type(MIME.from_path(file))
      |> send_file(200, file)
      |> halt()
    else
      conn
    end
  end

  defp accepts_html?(conn) do
    case get_req_header(conn, "accept") do
      [] ->
        true

      values ->
        Enum.any?(values, &(String.contains?(&1, "text/html") or String.contains?(&1, "*/*")))
    end
  end
end
