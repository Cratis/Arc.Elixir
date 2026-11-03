---
id: 0005-support-phoenix-and-liveview-through-the-same-pipelines
title: Support Phoenix and LiveView through the same pipelines
status: accepted
stage: none
class: contract
reversibility: costly
decided: 2026-11-03
decider: Arc.Elixir repository owner
applies-to:
  - Source/arc_phoenix/**
  - Source/arc_live_view/**
  - Documentation/**
---

<!-- Copyright (c) Cratis. All rights reserved. -->
<!-- Licensed under the MIT license. See LICENSE file in the project root for full license information. -->

> Amended by [0008](0008-ship-one-chronicle-only-package-with-opt-in-proxies.md): one package; no installer.

## Context

Phoenix applications serve either a single-page application over HTTP or server-rendered LiveView, often both. The same commands and queries should serve both.

## Decision

**Phoenix (`arc_phoenix`):**

- `arc_routes "/api"` in the router mounts the HTTP contract.
- The principal comes from the application's existing authentication through one configured function, for example one reading `current_scope` from `phx.gen.auth`. Arc does not introduce a parallel authentication system.
- The tenant resolver chain runs on Plug and reaches `Logger` metadata and, through `arc_ecto`, Ecto prefixes.
- A single-page fallback plug serves the built frontend and index document. Cookie-authenticated routes are protected by Phoenix CSRF handling, with the token passed through the client's header hook.
- An Igniter installer wires routes, configuration and generation.

**LiveView (`arc_live_view`):** LiveView calls the pipelines in-process, with no HTTP hop and no generated TypeScript.

- `on_mount {Arc.LiveView, :default}` builds the context from the session and socket and attaches the hook that applies query updates.
- `assign_query/4` reads once. `assign_observable/4` and `stream_query/4` subscribe and update assigns or streams.
- `execute_command/3` runs the full pipeline and returns the contract's result.
- `Arc.LiveView.Form.to_form(Command, params)` implements `Phoenix.HTML.FormData`, so the standard `<.form>` and `<.input>` components work. `phx-change` runs the validate path and maps results onto form errors by member.
- Authorization is re-evaluated on every command and subscription, not only at mount.

## Options considered

- **In-process pipeline calls from LiveView (chosen).** No serialization or network hop, one set of rules.
- **LiveView calls the HTTP routes.** Rejected: needless overhead and a second authentication path.
- **A Phoenix-only Arc without the contract.** Rejected: breaks the single-page application requirement.

## Default if unanswered

Support Phoenix 1.8 and LiveView 1.1 as the baseline.

## Timeline and scope

`arc_phoenix` follows the Plug host; `arc_live_view` follows the observable transports. Applies until superseded.

## Verification

- **Done when:** a sample application serves the same command to the single-page client and to a LiveView form, and a denied principal is rejected on both.
- **Verify by:** `Phoenix.LiveViewTest` with `arc_test`, and the runtime contract suite against the real client.

## Consequences

One slice serves both client styles. Spikes must confirm `Phoenix.HTML.FormData` works for a non-Ecto source and that the Mix compiler hook behaves under code reloading (decision 0007).

## Evidence

- Cratis/Arc `Documentation/http-contract.md` (working copy): identity and `/validate` contract.
