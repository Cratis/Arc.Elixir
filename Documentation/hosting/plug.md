---
title: Hosting on Plug
description: Mount Arc.Plug in any Plug pipeline to serve the Arc HTTP contract, with every route, status, header and transport it provides.
---

`Arc.Plug` serves the [Arc HTTP contract](/arc/http-contract/) from any Plug pipeline. That is what lets the existing frontend packages, and any HTTP client, talk to an Elixir backend.

```elixir
# From: Samples/plug/lib/counters/router.ex
defmodule Counters.Router do
  @moduledoc """
  A plain Plug pipeline: no Phoenix. Arc answers its own routes and passes everything else on.
  """

  use Plug.Router

  plug Arc.Plug, application: Counters.Arc
  plug :match
  plug :dispatch

  get "/health", do: send_resp(conn, 200, "ok")
  match _, do: send_resp(conn, 404, "not found")
end
```

Arc answers a request only when it is an Arc route. Everything else passes through untouched, so the plug can sit in front of the rest of your application. Start it under Bandit with `{Bandit, plug: Counters.Router, port: 4001}`; the sample's application module shows the supervision tree.

## Routes

| Route | Method | What it does |
| --- | --- | --- |
| a command route | `POST` | Executes the command; JSON body; returns the command result envelope |
| `<command route>/validate` | `POST` | Authorization and validation only |
| a query route | `GET` | Arguments in the query string |
| a query route | `QUERY` | Arguments, paging and sorting in a JSON body; responses carry `Cache-Control: no-store` |
| an observable query route | `GET` | Snapshot, or Server-Sent Events with `Accept: text/event-stream`, or a WebSocket upgrade |
| `/.cratis/queries/ws` | WebSocket | The multiplexed observable-query hub |
| `/.cratis/commands`, `/.cratis/queries` | `GET` | Operation catalogs; see [discovery routes](../authorization-and-identity.md#discovery-routes) |
| `/.cratis/me` | `GET` | The caller's [identity](../authorization-and-identity.md#identity-for-the-frontend); served only when an identity provider exists. Private: `Cache-Control: no-store, private` |
| `/.cratis/identity-details/schema` | `GET` | The JSON schema of the identity details type; `{}` without a typed provider |
| `/.cratis/users`, `/.cratis/tenants` | `GET` | Development users and tenants from your providers; `[]` without any |

Routes are derived from module names; see [How Arc works](../concepts.md#routes-come-from-module-names). The bodies are the [result envelopes](../results.md).

## Status codes

Selected in this order: success `200`; not authorized `403`; invalid `400`; query not ready `202`; exception `500`. An authentication handler that returns `:failed` gives `401`. A malformed body is a `400` with a `malformedRequest` result, never a `500`. A failed result never carries a `response` value.

## Headers

| Header | Behavior |
| --- | --- |
| `X-Correlation-ID` | A valid UUID is reused; anything else is replaced. The effective value is echoed on every Arc response and appears as `correlationId` in the envelope. Configurable with `correlation_header` |
| `X-Allowed-Severity` | The highest validation severity the caller tolerates, capped at `Warning`. See [Validation](../validation.md#tolerating-warnings) |
| `x-cratis-tenant-id` | Becomes `ctx.tenant`. Configurable with `tenant_header`. Arc does not enforce tenancy |

Header names are matched case-insensitively.

## Request bodies

Arc reads the body itself when `Plug.Parsers` has not. If you parse JSON earlier, Arc uses `conn.body_params`. The body limit is `max_body_bytes` (default 1,000,000); a larger body is a `400`. Unknown fields in a command body are ignored.

## Observable transports

- **Snapshot.** A plain `GET` returns the current result.
- **Server-Sent Events.** Each result is written as `data: {envelope}` followed by a blank line. A `: keep-alive` comment is sent every 15 seconds while idle so a closed connection is noticed.
- **WebSocket, direct.** Messages carry a `type` of `Data`, `Ping` or `Pong`.
- **WebSocket, hub.** `/.cratis/queries/ws` opens with `Connected` and then carries `Subscribe`, `Unsubscribe`, `QueryResult`, `Unauthorized`, `Error`, `Ping` and `Pong`, with per-subscription revisions. A denied subscription ends with `Unauthorized` for that query without disturbing the others.

All need the Arc application in your supervision tree. See [Queries](../queries.md#observable-queries) and the [limits](../limits-and-gaps.md).

## Verified with

The HTTP behavior is exercised against Bandit, and the proxy contract runs the real `@cratis/arc` client against it, including the `QUERY` method, the hub and Server-Sent Events. The WebSocket support uses `WebSock`, so other WebSock-capable servers should work; they are not part of the test matrix.

## Next steps

- [Hosting on Phoenix](phoenix.md) adds authentication, the SPA and LiveView.
- [Configuration](../configuration.md) lists every option.
