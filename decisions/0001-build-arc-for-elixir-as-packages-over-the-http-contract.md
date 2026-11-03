---
id: 0001-build-arc-for-elixir-as-packages-over-the-http-contract
title: Build Arc for Elixir as a family of packages over the Arc HTTP contract
status: accepted
stage: none
class: contract
reversibility: costly
decided: 2026-11-03
decider: Arc.Elixir repository owner
applies-to:
  - Source/**
  - Documentation/**
---

<!-- Copyright (c) Cratis. All rights reserved. -->
<!-- Licensed under the MIT license. See LICENSE file in the project root for full license information. -->

> Amended by [0008](0008-ship-one-chronicle-only-package-with-opt-in-proxies.md): one package, `cratis_arc`; no `arc_ecto`.

## Context

Arc exists for C#, Kotlin and Java, and as a Node.js source preview. Each keeps the same client packages (`@cratis/arc`, `@cratis/arc.react`, `@cratis/arc.react.mvvm`, Cratis Components) working by implementing the language-neutral HTTP contract. Elixir needs an implementation that is idiomatic rather than a translated one, supports Phoenix and LiveView explicitly, and still serves the regular single-page application stack.

## Decision

Arc for Elixir is a family of separately published Hex packages in one repository, under `Source/<package>/`, matching the layout Chronicle.Elixir uses.

| Package | Owns |
| --- | --- |
| `arc` | Schema, command and read-model DSL, pipelines, result envelopes, validation, authorization, identity, tenancy, correlation, telemetry, descriptors, and the proxy generator |
| `arc_plug` | The HTTP contract on Plug, including observable transports; runs on Bandit or Cowboy |
| `arc_phoenix` | Router macro, auth and tenancy integration, single-page fallback, installer |
| `arc_live_view` | LiveView integration |
| `arc_ecto` | Ecto-backed read models, paging, sorting, change notification |
| `arc_chronicle` | Appends events returned from commands through the Chronicle.Elixir client |
| `arc_test` | ExUnit scenarios that run the real pipelines |

Rules that hold for every package:

- The Arc HTTP contract is the compatibility surface. The existing frontend packages are used unchanged.
- The core imports no HTTP framework and no database. Ecto, Chronicle, Phoenix and Plug are reached only through the packages above.
- Parity with Arc on .NET is claimed per area, and only with a passing executable check. An unverified area is reported as unverified.
- The first releases are a source preview. No capability is documented as available before it is implemented and verified.

## Options considered

- **Packages over the contract (chosen).** Matches the other implementations and keeps each dependency optional.
- **One monolithic package.** Rejected: forces Phoenix, Ecto and Chronicle on every user.
- **A new client protocol or Elixir-specific frontend.** Rejected: discards the existing frontend packages and their tests.

## Default if unanswered

Work proceeds package by package in the order of decision 0007. Hex package names and the module namespace stay unresolved and block publishing only.

## Timeline and scope

Applies from now until superseded. Package boundaries may change before the first release; after it, moving a public module between packages is a breaking change.

## Verification

- **Done when:** a Phoenix application serves commands and queries to the unmodified `@cratis/arc` client, and the core compiles without Plug, Phoenix, Ecto or Chronicle on its dependency list.
- **Verify by:** `mix deps.tree` on the `arc` package, and the contract tests described in decision 0003.

## Consequences

Users install only what they need. Several packages mean several release streams to keep compatible. The shared contract bounds what Elixir can do differently on the wire.

## Evidence

- Cratis/Arc `Documentation/http-contract.md` and `Documentation/capabilities.md` (working copy; no release tag pinned).
- Cratis/Arc.TypeScript `Documentation/architecture.md` (working copy): core, host adapters and integrations split.
