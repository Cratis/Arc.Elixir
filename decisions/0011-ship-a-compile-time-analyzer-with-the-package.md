---
id: 0011-ship-a-compile-time-analyzer-with-the-package
title: Ship a compile-time analyzer with the package
status: accepted
stage: none
class: contract
reversibility: costly
decided: 2026-11-12
decider: Arc.Elixir repository owner
applies-to:
  - Source/arc/lib/arc/analyzer*
  - Source/arc/lib/mix/tasks/**
  - Documentation/code-analysis/**
---

<!-- Copyright (c) Cratis. All rights reserved. -->
<!-- Licensed under the MIT license. See LICENSE file in the project root for full license information. -->

## Context

Arc on .NET ships Roslyn analyzers (`ARC0001` and on) that catch misuse of Arc while compiling. Arc for Elixir had nothing equivalent: a command module that forgot `use Arc.Command`, or an observable query with nothing to watch, failed only at runtime. Chronicle.Elixir is building the same capability, and the two should look and behave alike so a consumer learns it once.

## Decision

- **A Mix compiler plus a compiler tracer, as Boundary does it.** `Mix.Tasks.Compile.ArcAnalyzer` registers `Arc.Analyzer` as a tracer, lets the Elixir compiler run, and then runs the rules over the facts the tracer collected. Findings are `Mix.Task.Compiler.Diagnostic`s, so CLI, CI and editors all show them.
- **Facts come from module attributes, not debug info.** Arc's macros leave their declarations in attributes, which are readable at the `:on_module` event, so the analyzer works with `debug_info: false`. Facts are kept in a manifest in `_build` so incremental builds report every finding.
- **The same shape as Chronicle.Elixir.** `Rule` has `id/0`, `description/0`, `default_severity/0` and optional `check_call/2`, `check_module/2` and `check_project/1`; rules return `Finding`s and the runner stamps the ID, the configured severity and the documentation link. Configuration is `config :cratis_arc, :analyzer` with `enabled` and `rules`; suppression is `@arc_analyzer ignore: [...]`; IDs are `ARCE####` (the Chronicle ones are `CHRE####`), so they never collide with the .NET IDs.
- **The compiler is `:arc_analyzer`, not `:arc`.** `:arc` is the proxy generator and runs after the Elixir compiler; the analyzer must run before it. Both can be used together.
- **An Igniter installer, optional.** `mix cratis_arc.install` (or `mix igniter.install cratis_arc`) puts the compiler in `mix.exs`, idempotently, for each app of an umbrella. Igniter is an optional dependency. This supersedes the "no installer" line of 0008.
- **Initial rules.** `ARCE0001` to `ARCE0005`, chosen to mirror the .NET rules where Elixir has the same mistake (`ARC0002`, `ARC0019`) and to add the Elixir-specific ones.

## Options considered

- **A Credo plugin.** Rejected for now: it needs a separate lint step. It can be added later over the same rules.
- **Reading debug info for every module.** Rejected: the attributes already hold what the rules need, and debug info can be switched off.
- **Reusing the `:arc` compiler name.** Rejected: one task cannot both register a tracer before the Elixir compiler and generate proxies after it, and renaming `:arc` would break existing projects.

## Consequences

- New rules can produce new warnings after an upgrade; the changelog says so for each release that adds one.
- Rules see declarations and calls, not the logic of a function body.
