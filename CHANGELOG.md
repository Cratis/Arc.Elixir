# Changelog

## Unreleased

### Added

- **Compile-time analyzer.** `compilers: [:arc_analyzer] ++ Mix.compilers()` (or `mix igniter.install cratis_arc`) checks your code against Arc rules on every compile and reports Mix diagnostics. Rules `ARCE0001` to `ARCE0005`, configurable per rule with `config :cratis_arc, :analyzer`. See [Code analysis](Documentation/code-analysis/index.md).

### Upgrading

- **New rules can produce new warnings.** Every release that adds a rule can make an existing build report findings it did not before, and `--warnings-as-errors` then fails it. Rules that find a likely bug (`ARCE0002`, `ARCE0005`) default to `:error`. Set a rule to `:warning` or `:off` under `config :cratis_arc, :analyzer, rules: [...]` while you fix the findings.
