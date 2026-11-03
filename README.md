# Arc for Elixir

Arc for Elixir is an opinionated CQRS application framework for Phoenix and Plug applications, with model-bound commands and queries, validation, authorization, observable queries, and generated TypeScript proxies for the existing Arc frontend packages.

> **Design phase.** No package is implemented or published yet. The accepted design is in [decisions/](decisions/index.md).

## What it will be

- The Arc [HTTP contract](https://github.com/Cratis/Arc/blob/main/Documentation/http-contract.md) on Plug, so `@cratis/arc`, `@cratis/arc.react` and Cratis Components work unchanged as a single-page application client.
- First-class Phoenix and LiveView support, calling the same commands and queries in-process.
- Idiomatic Elixir: macros and compile-time descriptors, an explicit context instead of dependency injection, tagged-tuple results, and OTP processes for observable queries.
- Optional integrations for Ecto and Chronicle. The core depends on neither.

## License

MIT. See [LICENSE](LICENSE).
