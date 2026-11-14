---
title: Code analysis
description: "The Arc analyzer for Elixir checks your code against Arc rules at every compile, in the terminal, editor and CI, needing only one line in mix.exs."
---

Arc ships a compile-time analyzer, the Elixir counterpart of the `ARC` Roslyn analyzers of [Arc on .NET](https://github.com/Cratis/Arc/tree/main/Documentation/backend/csharp/code-analysis). Its rules catch misuse of Arc, such as a command Arc never discovers or a query that never updates, while you compile instead of at runtime or in review.

Rules come with the `cratis_arc` package and version together with the APIs they protect. Findings are standard Mix diagnostics, so they show up in `mix compile`, in CI, and in editors that run the project's compilers (ElixirLS, Expert, Lexical).

## Set it up

Add the compiler ahead of the default compilers in `mix.exs`:

```elixir
def project do
  [
    app: :my_app,
    # ...
    compilers: [:arc_analyzer] ++ Mix.compilers()
  ]
end
```

Or let [Igniter](https://hexdocs.pm/igniter) do it. `mix igniter.install cratis_arc` adds the dependency and the compiler, and `mix cratis_arc.install` adds only the compiler. Running it again changes nothing, it keeps the compilers you already have, and in an umbrella it updates the `mix.exs` of every app in `apps/`.

That is the only step. New rules arrive with package upgrades.

`:arc_analyzer` is separate from the `:arc` compiler that [generates TypeScript proxies](../react-proxies.md). The analyzer has to run before the Elixir compiler so it can watch it; the proxy generator runs after it. Use both when you use both:

```elixir
compilers: [:arc_analyzer] ++ Mix.compilers() ++ [:arc]
```

## What a finding looks like

```text
warning: ARCE0003: MyApp.Authors.Listing.live/2 is an @observe query with no :watch and no
:topics, so it never pushes an update. Add `watch: [...]` or `topics: [...]`, or use @query.
  See https://www.cratis.io/arc/elixir/code-analysis/arce0003/
  └─ lib/my_app/authors/listing.ex:12
```

Each finding names the rule ID, the file and line, what is wrong, and a link to the rule's page.

## The rules

| ID | Rule | Kind | Default severity |
| --- | --- | --- | --- |
| [ARCE0001](ARCE0001.md) | A module declares a schema and `handle/2` but does not `use Arc.Command` | module | warning |
| [ARCE0002](ARCE0002.md) | A command or query is both anonymous and restricted | module | error |
| [ARCE0003](ARCE0003.md) | An `@observe` query has neither `:watch` nor `:topics` | module | warning |
| [ARCE0004](ARCE0004.md) | A command appends to Chronicle itself | call | warning |
| [ARCE0005](ARCE0005.md) | Two commands or queries resolve to the same route | project | error |

The kind says what the rule looks at: a *call* is one call to Chronicle, a *module* is how one module is declared, and a *project* rule compares modules with each other.

IDs are stable and never reused. `ARCE` stands for Arc for Elixir; the same ideas on .NET have `ARC` IDs, and a rule page names its .NET counterpart when there is one.

## Configure the rules

Everything is optional. Without configuration every rule runs at its default severity.

```elixir
# config/config.exs
config :cratis_arc, :analyzer,
  enabled: true,
  segments_to_skip: 1,
  rules: [
    {"ARCE0001", :error},
    {"ARCE0003", :off}
  ]
```

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | `false` switches the whole analyzer off. The compiler then does nothing |
| `rules` | `[]` | `{id, severity}` pairs. Severity is `:error`, `:warning`, `:info` or `:off` |
| `segments_to_skip` | `1` | Use the same value as `use Arc.Application`, so [ARCE0005](ARCE0005.md) computes the routes you serve |

A rule that is not listed keeps its default. An unknown rule ID or a severity that does not exist is reported as a warning, so a typo does not silently turn a rule off.

| Severity | Effect |
| --- | --- |
| `:error` | Reported as an error. The build fails |
| `:warning` | Reported as a warning |
| `:info` | Reported as information. Never fails the build |
| `:off` | The rule does not run |

`mix compile --warnings-as-errors` fails on `:warning` findings the same way it does for compiler warnings, which is how to hold a CI build to zero findings.

## Turn a rule off for one module

When a rule is wrong for one module, say so in the module:

```elixir
defmodule MyApp.Legacy.Register do
  use Arc.Schema

  @arc_analyzer ignore: ["ARCE0001"]

  # ...
end
```

The module's findings for those rules are dropped, and nothing else changes. Prefer fixing the code; use this for a deliberate exception, and say why in a comment.

## What it analyzes

- **Only your own code.** Dependencies are compiled without the analyzer, so you never see findings about code you do not own.
- **Everything it needs comes from the compiler.** Arc's macros leave their declarations in module attributes, so the analyzer does not need `debug_info`, and works with `debug_info: false`.
- **Facts are kept between builds.** The Elixir compiler recompiles only what changed. The analyzer keeps what it learned about every module in a manifest in `_build`, so an incremental build that touches one file still reports the findings of all the others. `mix clean` removes the manifest.

The cost is small: the compiler notes a module's declarations as it finishes it, and the rules run once over the result.

## Supported versions

Elixir 1.18 or later, the same as `cratis_arc`. CI builds and tests with Elixir 1.19.5 on OTP 28.5.

## Related

- [Configuration reference](../configuration.md)
- [Commands](../commands.md) and [Queries and read models](../queries.md), which the rules protect
