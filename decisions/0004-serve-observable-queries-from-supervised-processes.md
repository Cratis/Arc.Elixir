---
id: 0004-serve-observable-queries-from-supervised-processes
title: Serve observable queries from supervised processes
status: accepted
stage: none
class: contract
reversibility: costly
decided: 2026-11-03
decider: Arc.Elixir repository owner
applies-to:
  - Source/arc/**
  - Source/arc_plug/**
  - Source/arc_ecto/**
---

<!-- Copyright (c) Cratis. All rights reserved. -->
<!-- Licensed under the MIT license. See LICENSE file in the project root for full license information. -->

## Context

The HTTP contract defines observable queries over an HTTP snapshot, direct SSE, direct WebSocket and multiplexed hubs, with revisions, `changeSet` deltas and per-subscription authorization. Elixir has processes, supervision and Registry, which fit this directly.

## Decision

- Each subscription is one process under a dynamic supervisor owned by the `Arc.Application`. It monitors the transport process and ends when it ends. Subscription processes use `restart: :temporary`, so a failing subscription cannot restart and fail in a loop.
- `observe` queries declare notification topics. A notifier behaviour triggers a re-run. The default notifier uses `:pg`; `arc_phoenix` supplies `Phoenix.PubSub`; `arc_ecto` may add database notification.
- Arc computes `changeSet` deltas by diffing re-run results by the read model key.
- Transports follow the HTTP contract exactly: WebSocket through `WebSock`, SSE through chunked Plug responses, and the hub messages, revisions and ownership rules as specified. Each subscription is authorized independently by the ordinary pipeline.
- Background work that Arc runs on the application's behalf uses an explicit error policy: retry, retry after a delay, skip, or stop.

## Options considered

- **One supervised process per subscription (chosen).** Natural isolation, cleanup on disconnect, backpressure per subscriber.
- **A single broadcaster process.** Rejected: one slow subscriber affects all, and authorization per subscription is harder.
- **Polling only.** Rejected: does not meet the observable contract.

## Default if unanswered

Notification-driven re-run with the `:pg` notifier.

## Timeline and scope

After the Plug host and proxy generator. Applies until superseded.

## Verification

- **Done when:** a hub test subscribes, receives the first result, receives a delta after a notification, and sees `Unauthorized` for a denied subscription without disturbing others.
- **Verify by:** ExUnit transport tests plus the runtime contract suite against the real client.

## Consequences

Subscriptions scale with the Erlang VM's process model. Re-run on notification costs a query per change, so notification topics should be specific.

## Evidence

- Cratis/Arc `Documentation/http-contract.md` (working copy): observable query transport and multiplexed hubs.
- Commanded v1.4.11 handler documentation (https://commanded.hexdocs.pm/Commanded.Event.Handler.html): restart loops when a supervised handler reprocesses the same failing event.
