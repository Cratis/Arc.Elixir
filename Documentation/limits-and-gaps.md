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
| The result envelopes, field for field | `Arc.EnvelopeTest` pins the exact key sets and types of both |
| Identity: `/.cratis/me`, the details schema, development users and tenants, trusted client principal headers | The identity specs, and the real `IdentityProvider` in the contract run |
| Generated TypeScript: deterministic, strict compilation, runtime behavior with the real client | `ContractTests/run.sh`, including commands, validation, authorization, queries, paging, sorting, `QUERY`, the WebSocket hub and Server-Sent Events |
| LiveView forms, observable assigns, authorization on every call | The LiveView specs |

Not verified: behavior against a running Chronicle kernel in this repository's CI. The in-memory kernel runs appends and constraints, but not read-model queries. The samples document how to run against a development kernel.

## Where it differs from the HTTP contract

- **Change sets.** Delta and unspecified transfer modes compute the change set on the hub, per subscription, by comparing with the previous emission, so a restart of a subscription starts with a snapshot again. Items are matched on an `id` member (any case); without one, the change set lists additions and removals only and never a replacement. A query that is ordered or paged always sends the snapshot too, because a position matters there.
- **SSE hub control requests are per request.** A subscription runs with the context of the control `POST` that created it, so the tenant of a subscription is the tenant header or cookie of that request, not of the stream. The caller of a control request must be the caller that opened the stream (same principal id), else the answer is 404.
- **Introspection depth.** The catalogs report name, namespace, route, type, documentation summary and a payload or arguments schema. They do not report authorization or per-property validation metadata.
- **Tenancy.** One configured resolver (header, query string, claim, subdomain, fixed or a module, see `Arc.Tenancy`) selects the tenant; there is no chain of resolvers, and Arc does not require or enforce a tenant or check membership. A named tenant also selects the Chronicle namespace. `/.cratis/tenants` only lists what your providers return.
- **MongoDB.** `cratis_arc_mongodb` is not a port of the MongoDB C# driver conventions: documents are structs converted by `Arc.MongoDB.Codec`, there are no `IMongoCollection` injection, no serializers for `Guid` representations other than the standard one and no `MONGODB-OIDC` access tokens (the Elixir driver has none). See [MongoDB](mongodb.md).
- **Identity cookie.** `/.cratis/me` never sets or reads a `.cratis-identity` cookie.
- **Replay memory.** The signed forwarded-identity and on-behalf-of replay caches live in a process per application and per node. A replay is refused on the node that saw the original only, and verification fails closed if the application is not started.
- **Admission control.** The only request limit is `max_body_bytes`. There are no connection or subscription caps.
- **`X-Allowed-Severity`.** Read on commands only, as a number, and capped at `Warning`.

## Authoring limits

- Nested lists, enums and derived types are not supported in schemas or generated proxies.
- A command has one `key` field.
- Sorting uses top-level fields of the model struct, in memory. Page in the database and return an `Arc.Page` for large collections.
- `Arc.Notifier` reaches subscriptions on one node. Fan out across nodes yourself with `Phoenix.PubSub`.
- `Arc.LiveView` has no stream helper; observable assigns replace whole lists.
- The [analyzer](code-analysis/index.md) reads Arc's declarations and the calls the compiler reports, not the logic inside `handle/2`. It cannot tell what a function returns, so it has no rule about result shapes, and it sees a Chronicle call only when it is written as a call to a `Chronicle` module.

## Chronicle behavior to know

- The projection that builds a read model is asynchronous. A query right after a command may not see its effect yet; observable queries and LiveView assigns catch up on their own.
- A returned event needs a `key: true` field, or an explicit `{event_source_id, event}`.

## Next steps

If a gap blocks you, open an issue on [Cratis/Arc.Elixir](https://github.com/Cratis/Arc.Elixir/issues) with the case. Gaps are closed for demonstrated needs.
