# Changelog

## Unreleased

### Added

- **Availability.** The same model as Arc for .NET: audiences, blocks (`for`, `when`, `with`, `not`), gates on module, feature, slice, command and query, and suspension. One gate runs first in the pipeline with the reasons `NotAvailable` and `Suspended` (`403`) and a retryable `503`; `/.cratis/availability`, the shared manifest, proxies that carry part identity and a LiveView component. See Documentation/availability.md.
- **Proxy generation for nested lists, enums and derived types.**

- **Compile-time analyzer.** `compilers: [:arc_analyzer] ++ Mix.compilers()` (or `mix igniter.install cratis_arc`) checks your code against Arc rules on every compile and reports Mix diagnostics. Rules `ARCE0001` to `ARCE0005`, configurable per rule with `config :cratis_arc, :analyzer`. See [Code analysis](Documentation/code-analysis/index.md).

- **Explicit command names.** `command "register-author"` after `use Arc.Command` sets the last segment of the command's route, so renaming or moving the module no longer changes the API. It is optional: without it the route still follows the module name. The name must be kebab-case (checked at compile time), the descriptor exposes it as `route_name`, and `ARCE0005` routes by it. See [Routes come from module names](Documentation/concepts.md#routes-come-from-module-names).

- **Event model explorer.** `/.cratis/event-model`, the same address and routes as the C# Arc, draws your commands, events, read models and reactions as an event model, with the Screenplay source beside it. Add `compilers: Mix.compilers() ++ [:arc_event_model]` and `arc: [application: MyApp.Arc]`: the model is generated while you compile and embedded in your application's `priv`, and the explorer ships inside the package. It is served in development by default (`event_model:`), and `introspection` decides who may read it. See [Event model](Documentation/event-model.md).

### Upgrading

- **New rules can produce new warnings.** Every release that adds a rule can make an existing build report findings it did not before, and `--warnings-as-errors` then fails it. Rules that find a likely bug (`ARCE0002`, `ARCE0005`) default to `:error`. Set a rule to `:warning` or `:off` under `config :cratis_arc, :analyzer, rules: [...]` while you fix the findings.
