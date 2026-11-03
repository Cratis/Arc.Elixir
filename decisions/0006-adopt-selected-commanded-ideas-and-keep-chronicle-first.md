---
id: 0006-adopt-selected-commanded-ideas-and-keep-chronicle-first
title: Adopt selected Commanded ideas and keep Chronicle the first event-sourcing integration
status: accepted
stage: none
class: contract
reversibility: costly
decided: 2026-11-03
decider: Arc.Elixir repository owner
applies-to:
  - Source/arc/**
  - Source/arc_chronicle/**
  - Source/arc_test/**
---

<!-- Copyright (c) Cratis. All rights reserved. -->
<!-- Licensed under the MIT license. See LICENSE file in the project root for full license information. -->

## Context

Commanded is the established Elixir CQRS and event-sourcing library. It is aggregate-centric and runs on its own event store. Chronicle uses a server kernel with constraints and decision reads. The fetched Commanded documentation describes no built-in command validation, authorization, identity, tenancy, HTTP contract or frontend proxies, which is the space Arc fills.

## Decision

**Adopt:**

1. An application module (`use Arc.Application`), as Commanded uses `use Commanded.Application`, instead of global configuration.
2. Dispatch from code with a `returning:` option: `Arc.dispatch(MyApp.Arc, command, returning: :response | :result | :events)`, where `:result` is the full envelope.
3. Tracing identifiers on the context: correlation and causation identifiers and a metadata map. `arc_chronicle` maps them onto Chronicle's causation chain.
4. An opt-in read-your-writes option in `arc_chronicle`, `await: [ReadModel]`, off by default and documented as not transactional.
5. Explicit command timeouts, carried as a deadline on the context.
6. An error-policy vocabulary for background work Arc runs: retry, retry after a delay, skip, stop, with the restart-loop caution of decision 0004.
7. Test helpers that wait for events, so tests never sleep.

**Do not adopt:** aggregate processes (Chronicle's constraints and decision reads cover concurrency), process managers and event handlers (Chronicle.Elixir owns reactors), and a central router listing every command (discovery within an `Arc.Application` replaces it).

An `arc_commanded` adapter is not planned. It is added only for a named consumer with a concrete requirement.

## Options considered

- **Selective adoption with Chronicle first (chosen).** Takes proven ergonomics without a second event-sourcing model.
- **Build on Commanded as the event-sourcing layer.** Rejected: duplicates Chronicle and changes the consistency model.
- **Ignore Commanded.** Rejected: its dispatch, tracing and consistency ergonomics are worth matching.

## Default if unanswered

Items 1 to 3 and 5 land in the core; 4 and 6 land with `arc_chronicle`; 7 lands with `arc_test`.

## Timeline and scope

Applies from the core milestone until superseded. Reopen the adapter question when a consumer supplies a concrete contract.

## Verification

- **Done when:** each adopted item has a spec that exercises it through the public API.
- **Verify by:** `mix test` for the owning package.

## Consequences

Users familiar with Commanded find familiar dispatch and tracing, but no aggregate layer. A Commanded user can still call a Commanded router from `handle`.

## Evidence

- Commanded v1.4.11: router (https://commanded.hexdocs.pm/Commanded.Commands.Router.html), process managers (https://commanded.hexdocs.pm/process-managers.html), event handlers (https://commanded.hexdocs.pm/Commanded.Event.Handler.html). The middleware callback names were not on the fetched router page and are not relied on here.
