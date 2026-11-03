---
id: 0002-use-macros-descriptors-and-an-explicit-context-for-authoring
title: Author commands and queries with macros, compile-time descriptors and an explicit context
status: accepted
stage: none
class: contract
reversibility: costly
decided: 2026-11-03
decider: Arc.Elixir repository owner
applies-to:
  - Source/arc/**
  - Documentation/**
---

<!-- Copyright (c) Cratis. All rights reserved. -->
<!-- Licensed under the MIT license. See LICENSE file in the project root for full license information. -->

> Amended by [0008](0008-ship-one-chronicle-only-package-with-opt-in-proxies.md): handler results are `{:append, …}`, `{:ok, response}` or `{:error, results}`.

## Context

Other Arc implementations use attributes or annotations plus a dependency injection container. Elixir has neither classes nor a standard container. Its idioms are modules, structs, macros, behaviours, tagged tuples and OTP supervision.

## Decision

- **Artifacts are modules.** `use Arc.Command` and `use Arc.ReadModel` define the artifact. A `schema do ... end` block declares fields (primitives, enums, nested structs, lists, maps, and `Arc.Concept` value types) and generates the struct and typed metadata.
- **Descriptors are generated at compile time** as `__arc__/0` on each artifact. Discovery filters the application's module list; there is no runtime reflection over source.
- **No dependency injection.** Handlers call `Repo` and context modules directly. Request-scoped facts travel in an explicit `%Arc.Context{}` argument: principal, tenant, correlation and causation identifiers, metadata, and a deadline. The same values are set as `Logger` metadata.
- **Results are tagged tuples.** A handler returns `:ok`, `{:ok, response}` or `{:error, validation}`. A command either records what happened or is rejected; it never succeeds as a silent no-op.
- **Pipeline order** is authenticate, authorize, validate, `provide`, `handle`, response handlers. Filters, execution scopes and policies are behaviours. Telemetry is emitted as `[:arc, :command | :query, ...]` events.
- **Queries** are declared with `query name, args do ... end` and `observe name, opts do ... end`, which define functions taking the context and the arguments.
- **An application module owns the runtime.** `use Arc.Application, otp_app: :my_app` defines a supervised unit that scopes discovery, configuration and observable-query processes. There is no global configuration.
- **Wire naming.** Struct fields are snake_case; the wire and the generated TypeScript use camelCase.
- **Validation** is Arc's own rule set, extractable for the client. Ecto changesets are an optional bridge in `arc_ecto`.

## Options considered

- **Macros and descriptors (chosen).** Idiomatic, compile-time checked, no runtime reflection.
- **Port the DI container and attributes.** Rejected: foreign to Elixir and hides data flow.
- **Ecto embedded schemas as the core model.** Rejected: puts a database toolkit under the core and its non-SQL users.
- **Global application configuration.** Rejected: blocks isolated tests and multiple Arc applications in one VM.

## Default if unanswered

The DSL spelling above is the working shape. Exact macro names may change until the first release.

## Timeline and scope

Applies to the `arc` core from the first milestone. After the first release, macro names and the context fields are public API.

## Verification

- **Done when:** a command and a read model compile with descriptors, pass through the pipeline in an ExUnit scenario, and return contract-shaped envelopes.
- **Verify by:** `mix compile --warnings-as-errors`, `mix test`, `mix format --check-formatted`.

## Consequences

Authors write plain Elixir with explicit data flow. Users who expect injection must pass collaborators through the context or call modules directly.

## Evidence

- Cratis/Arc `.cratis/ai/rules/elixir.md` (working copy): Elixir and OTP idioms, `@spec`, supervision.
- Cratis/Arc `.cratis/ai/rules/project/command-handler-results.md` (working copy): no optional event results.
