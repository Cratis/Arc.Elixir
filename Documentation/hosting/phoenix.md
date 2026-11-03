---
title: Hosting on Phoenix
description: Wire Arc into a Phoenix endpoint, reuse phx.gen.auth, serve a React app from the same origin, and keep cookie-based sessions safe.
---

Phoenix needs no adapter. `Arc.Plug` goes in the endpoint, before the router, and the rest is your application.

```elixir
# From: Samples/phoenix/lib/library/web/endpoint.ex
      plug Plug.RequestId
      plug Plug.Session, @session_options

      # Who is calling: turns the demo sign-in into the principal Arc reads.
      plug Library.Web.DevAuth

      # The Arc HTTP contract: commands, queries, observable queries and /.cratis/*.
      # Non-Arc requests pass through to the rest of the pipeline.
      plug Arc.Plug, application: Library.Arc
```

Put it in the endpoint rather than a router scope because Arc owns paths such as `/api/…` and `/.cratis/…`, and a Phoenix router has no use for them.

## Authentication

Place `Arc.Plug` after whatever authenticates the request. With `phx.gen.auth`, Arc understands `conn.assigns.current_scope`. For anything else, see [Authorization and identity](../authorization-and-identity.md#tell-arc-who-is-calling).

## A React app on the same origin

Serving the built frontend from Phoenix means one origin: no CORS, and cookies work. `Arc.Plug.SinglePage` serves static files and returns `index.html` for any other `GET` that accepts HTML, so client-side routes survive a refresh. It never answers API paths.

```elixir
# From: Samples/phoenix/lib/library/web/spa.ex
    root = Application.app_dir(:library, "priv/spa")

    if File.dir?(root) do
      Arc.Plug.SinglePage.call(
        conn,
        Arc.Plug.SinglePage.init(
          root: root,
          api_prefixes: ["/api/", "/.cratis/", "/live", "/assets", "/health"]
        )
      )
    else
      conn
    end
```

List every prefix your own routes use in `api_prefixes` (the LiveView socket and pages, assets, health checks), because a client-side route fallback would otherwise swallow them. During development, run `vite` with its proxy to Phoenix instead; the sample's `vite.config.ts` does.

## Proxies follow your edits

If you opt in to [generated proxies](../react-proxies.md), the `:arc` compiler regenerates them on every compile. Phoenix's code reloader runs the project compilers, so `mix phx.server` keeps the TypeScript current as you edit commands.

## The formatter

Arc exports its declaration macros to the formatter. Add it to `.formatter.exs` so `field :name, :string` is not rewritten with parentheses:

```elixir
[
  import_deps: [:cratis_arc, :phoenix],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

Chronicle's own macros (`unique`, `from`) are not exported by `cratis_chronicle`; list the ones you use under `locals_without_parens`, as the sample does.

## CSRF and cookie sessions

Arc does not verify CSRF tokens, and because `Arc.Plug` runs before the router, Phoenix's `:protect_from_forgery` does not cover Arc routes. This matters only if browsers authenticate to Arc with an ambient credential such as a session cookie, because then a hostile page can make the browser send an authenticated command.

If you authenticate with a cookie, require a header that a cross-site form cannot set, and reject requests without it. A small plug in front of `Arc.Plug` is enough:

```elixir
defmodule MyAppWeb.RequireClientHeader do
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(%{method: method} = conn, _opts) when method in ["POST", "PUT", "PATCH", "DELETE"] do
    case get_req_header(conn, "x-requested-with") do
      ["arc"] -> conn
      _ -> conn |> send_resp(403, "Missing client header") |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
```

The React client adds headers you choose through the `httpHeadersCallback` prop of `<Arc>`. Authenticating with a bearer token in `Authorization` has no such exposure. LiveView forms are covered by Phoenix's own socket origin and token checks.

## Next steps

- [LiveView](../live-view.md) for server-rendered pages on the same commands and queries.
- [Samples](../samples.md) to run all of this.
