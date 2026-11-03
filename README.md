# Arc for Elixir

Arc for Elixir is an opinionated CQRS application framework for Phoenix and Plug on [Cratis Chronicle](https://github.com/Cratis/Chronicle), with model-bound commands and queries, validation, authorization, observable queries and opt-in TypeScript proxies for React.

[![Hex.pm](https://img.shields.io/hexpm/v/cratis_arc.svg)](https://hex.pm/packages/cratis_arc)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/cratis_arc)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Discord](https://img.shields.io/discord/1182595891576717413?label=Discord&logo=discord&color=7289da)](https://discord.gg/kt4AMpV8WV)

> **Source preview.** The package is built and tested here, but the API may still change, and nothing is claimed beyond what [Limits and gaps](Documentation/limits-and-gaps.md) says is verified.

## Overview

You write a command or a query as a plain module. Arc binds, validates, authorizes and runs it, records the events it returns in Chronicle, and serves it to React, LiveView or any HTTP client.

```elixir
defmodule Library.Authors.Registration.RegisterAuthor do
  @moduledoc "Registers a new author."

  use Arc.Command

  schema do
    field :id, Library.Authors.AuthorId, key: true, required: true
    field :name, :string, required: true, min_length: 2, max_length: 50
  end

  def handle(%__MODULE__{name: name}, _ctx),
    do: {:append, %Library.Authors.AuthorRegistered{name: name}}
end
```

- **`use Arc.Command` / `use Arc.ReadModel`** — declare commands and queries; fields, rules and authorization are declarations, `handle/2` is the logic
- **The Arc HTTP contract on Plug** — `@cratis/arc`, `@cratis/arc.react` and Cratis Components work against it unchanged
- **Phoenix and LiveView** — the same commands and queries, in process, with forms that show pipeline errors on the right field
- **Observable queries** — re-run when Chronicle changes a read model, pushed over WebSocket or Server-Sent Events
- **Opt-in TypeScript proxies** — `mix arc.gen.proxies` generates typed commands and queries, with the same validation as the server, only if you add the compiler
- **Identity** — `/.cratis/me`, typed identity details, development users for Lens, and trusted `x-ms-client-principal` headers behind an ingress
- **The exact result envelopes** — `CommandResult` and `QueryResult` match the Arc contract field for field, pinned by specs
- **Chronicle underneath** — returned events are appended with the caller's identity and correlation; constraint rejections reach the client as validation results
- **`Arc.Test`** — the real pipeline against Chronicle's in-memory kernel

Arc for Elixir works with Chronicle only. It is part of the Cratis family of Arc implementations for [.NET](https://github.com/Cratis/Arc), [Kotlin and Java](https://github.com/Cratis/Arc.Kotlin), [Go](https://github.com/Cratis/Arc.Go) and [TypeScript](https://github.com/Cratis/Arc.TypeScript), and follows the same [HTTP contract](https://github.com/Cratis/Arc/blob/main/Documentation/http-contract.md).

## Install

```elixir
defp deps do
  [
    {:cratis_arc, "~> 0.1"}
  ]
end
```

Arc needs Elixir 1.18 or later and brings `cratis_chronicle` with it. Phoenix, Phoenix.HTML and Phoenix LiveView are optional: the LiveView support compiles only when `phoenix_live_view` is a dependency. CI builds and tests with Elixir 1.19.5 on Erlang/OTP 28.5.

Add `import_deps: [:cratis_arc]` to `.formatter.exs` so `field :name, :string` is not rewritten with parentheses.

## Prerequisite: Chronicle running

```bash
docker pull cratis/chronicle:latest-development
docker run -d --name chronicle \
  -p 127.0.0.1:35000:35000 \
  -p 127.0.0.1:27017:27017 \
  cratis/chronicle:latest-development
```

The `127.0.0.1:` prefixes keep both ports on your machine: the development kernel accepts well-known credentials and its MongoDB has no authentication.

## Getting started

[Get started](Documentation/get-started.md) builds an authors feature end to end: events, a command, a query, the HTTP API, a LiveView page and a test.

## Documentation

- [How Arc works](Documentation/concepts.md)
- [Result envelopes](Documentation/results.md), [Commands](Documentation/commands.md), [Queries and read models](Documentation/queries.md), [Validation](Documentation/validation.md), [Authorization and identity](Documentation/authorization-and-identity.md)
- [Hosting on Plug](Documentation/hosting/plug.md) and [on Phoenix](Documentation/hosting/phoenix.md)
- [LiveView](Documentation/live-view.md)
- [React and generated proxies](Documentation/react-proxies.md)
- [Testing](Documentation/testing.md), [Observability](Documentation/observability.md), [Configuration](Documentation/configuration.md)
- [Samples](Documentation/samples.md) and [Limits and gaps](Documentation/limits-and-gaps.md)
- [Build and release](Documentation/contributing/build-and-release.md) — the pull request checks and the publishing pipeline

## Samples

| Sample | Shows |
| --- | --- |
| [`Samples/plug`](Samples/plug) | The smallest Arc application: Bandit and a Plug router |
| [`Samples/phoenix`](Samples/phoenix) | The HTTP contract, LiveView and a React app served from one Phoenix endpoint |
| [`Samples/frontend`](Samples/frontend) | A React app on the generated proxies |

`Samples/run-tests.sh` builds and tests all three.

## Contributing

```bash
cd Source/arc
mix deps.get
mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
mix test

cd ../..
Samples/run-tests.sh
ContractTests/run.sh
```

Pull requests need exactly one release label (`major`, `minor`, `patch` or `no-release`) and a description written as a release note; [Build and release](Documentation/contributing/build-and-release.md) explains both. Design decisions are recorded in [`decisions`](decisions/index.md). Questions and ideas are welcome on [Discord](https://discord.gg/kt4AMpV8WV); report confirmed bugs as [issues](https://github.com/Cratis/Arc.Elixir/issues).

## License

MIT. See [LICENSE](LICENSE).
