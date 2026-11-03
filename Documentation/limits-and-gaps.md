---
title: Limits and gaps
description: What Arc for Elixir does not do yet, where it differs from Arc on .NET, and what is verified, so you can decide whether it fits before you build on it.
---

Arc for Elixir is a source preview. This page states what it does not do, so you can find the edge before you hit it. It makes no claim of parity with Arc on .NET; only the behaviors named as verified have an executable check behind them.

## When this is the wrong fit

- You do not use Chronicle. Arc for Elixir works with Chronicle only; there is no other persistence.
- You need a feature of Arc on .NET that is not listed as present here, for example the controller-based endpoints or a tenant resolver chain.
- You need Cowboy-specific behavior verified. The HTTP behavior is exercised against Bandit.

## What is verified

| Area | Check |
| --- | --- |
| Command and query pipeline, validation, authorization, appends, constraint mapping | The `Source/arc` and sample specs, against Chronicle's in-memory kernel |
| HTTP routes, statuses, correlation, paging, sorting, the `QUERY` method, introspection | The Plug specs |
| Generated TypeScript: deterministic, strict compilation, runtime behavior with the real client | `ContractTests/run.sh`, including commands, validation, authorization, queries, paging, sorting, `QUERY`, the WebSocket hub and Server-Sent Events |
| LiveView forms, observable assigns, authorization on every call | The LiveView specs |

Not verified: behavior against a running Chronicle kernel in this repository's CI. The in-memory kernel runs appends and constraints, but not read-model queries. The samples document how to run against a development kernel.

## Where it differs from the HTTP contract

- **Delta transfer mode.** A hub subscription that asks for `transferMode: "delta"` receives full snapshots with no change set.
- **No SSE hub.** `/.cratis/queries/sse` and its subscribe and unsubscribe routes are not served. Use the WebSocket hub (the client default) or direct Server-Sent Events per query.
- **Introspection depth.** The catalogs report name, namespace, route, type, documentation summary and a payload or arguments schema. They do not report authorization or per-property validation metadata.
- **Tenancy.** The tenant header is read into `ctx.tenant`. Arc has no resolver chain and does not require or enforce a tenant.
- **Identity cookie.** `/.cratis/me` never sets a `.cratis-identity` cookie.
- **Admission control.** The only request limit is `max_body_bytes`. There are no connection or subscription caps.
- **`X-Allowed-Severity`.** Read on commands only, as a number, and capped at `Warning`.

## Authoring limits

- Nested lists, enums and derived types are not supported in schemas or generated proxies.
- A command has one `key` field.
- Sorting uses top-level fields of the model struct, in memory. Page in the database and return an `Arc.Page` for large collections.
- `Arc.Notifier` reaches subscriptions on one node. Fan out across nodes yourself with `Phoenix.PubSub`.
- `Arc.LiveView` has no stream helper; observable assigns replace whole lists.

## Chronicle behavior to know

- The projection that builds a read model is asynchronous. A query right after a command may not see its effect yet; observable queries and LiveView assigns catch up on their own.
- A returned event needs a `key: true` field, or an explicit `{event_source_id, event}`.

## Next steps

If a gap blocks you, open an issue on [Cratis/Arc.Elixir](https://github.com/Cratis/Arc.Elixir/issues) with the case. Gaps are closed for demonstrated needs.
