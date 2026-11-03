---
id: 0007-set-baselines-milestones-and-spikes-for-the-first-release
title: Set baselines, milestones and spikes for the first release
status: accepted
stage: none
class: scope
reversibility: cheap
decided: 2026-11-03
decider: Arc.Elixir repository owner
applies-to:
  - Source/**
  - .github/**
---

<!-- Copyright (c) Cratis. All rights reserved. -->
<!-- Licensed under the MIT license. See LICENSE file in the project root for full license information. -->

> Amended by [0008](0008-ship-one-chronicle-only-package-with-opt-in-proxies.md): milestones 7 and 8 collapsed; Hex name and namespace resolved.

## Context

Decisions 0001 to 0006 fix the architecture. This record fixes the baselines, the order of delivery, and the unverified assumptions that must be settled before the affected work is built.

## Decision

**Baselines:** Elixir `~> 1.18` (matching Chronicle.Elixir), Phoenix 1.8, LiveView 1.1. Every `.ex` and `.exs` file carries the standard license header. The quality gates are `mix compile --warnings-as-errors`, `mix test` and `mix format --check-formatted`.

**Milestones, in order:**

1. Mix project, CI and corpus setup for the first package.
2. Core: schema, DSL, pipeline, envelopes, validation, authorization, `arc_test`.
3. `arc_plug` and `arc_phoenix`: commands, queries, introspection, identity.
4. Proxy generator with its contract and differential gates.
5. Observable queries over SSE and WebSocket.
6. `arc_live_view`.
7. `arc_ecto`.
8. `arc_chronicle`.

**Spikes before the dependent work starts:**

- Whether Plug with Bandit and Cowboy routes the custom `QUERY` verb (milestone 3).
- Whether `Phoenix.HTML.FormData` works cleanly for a non-Ecto form source (milestone 6).
- Whether a Mix compiler hook for generation behaves under `phx.server` code reloading (milestone 4).

**Open items:** Hex package names (`arc` is likely taken) and the module namespace; both block publishing only.

## Options considered

- **Core and Phoenix first (chosen).** Delivers the stated priority early.
- **Ecto and Chronicle first.** Rejected: persistence without a way to serve it proves little.

## Default if unanswered

Proceed in the order above; settle naming before the first publish.

## Timeline and scope

Reviewed at the end of each milestone. Cheap to change.

## Verification

- **Done when:** each spike has a recorded outcome and, if it changes a decision, a superseding record.
- **Verify by:** a short spike note in the pull request that resolves it, and the gates above in CI.

## Consequences

The order front-loads the contract and Phoenix. A failed spike may change the affected package's design, which is why spikes precede it.

## Evidence

- Cratis/Arc `.cratis/ai/rules/elixir.md` (working copy): Elixir version and gates, grounded in Chronicle.Elixir v3.13.0.
