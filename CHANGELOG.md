# Changelog

## Unreleased

### Added

- **Availability.** The same model as Arc for .NET: audiences, blocks (`for`, `when`, `with`, `not`), gates on module, feature, slice, command and query, and suspension. One gate runs first in the pipeline with the reasons `NotAvailable` and `Suspended` (`403`) and a retryable `503`; `/.cratis/availability`, the shared manifest, proxies that carry part identity and a LiveView component. See Documentation/availability.md.
- **Proxy generation for nested lists, enums and derived types.**

- **Compile-time analyzer.** `compilers: [:arc_analyzer] ++ Mix.compilers()` (or `mix igniter.install cratis_arc`) checks your code against Arc rules on every compile and reports Mix diagnostics. Rules `ARCE0001` to `ARCE0005`, configurable per rule with `config :cratis_arc, :analyzer`. See [Code analysis](Documentation/code-analysis/index.md).

- **Explicit command names.** `use Cratis.Arc.Command, id: "register-author"` sets the last segment of the command's route, so renaming or moving the module no longer changes the API. It is optional: without it the route still follows the module name. The name must be kebab-case (checked at compile time), the descriptor exposes it as `route_name`, and `ARCE0005` routes by it. See [Routes come from module names](Documentation/concepts.md#routes-come-from-module-names).

- **Event model explorer.** `/.cratis/event-model`, the same address and routes as the C# Arc, draws your commands, events, read models and reactions as an event model, with the Screenplay source beside it. Add `compilers: Mix.compilers() ++ [:arc_event_model]` and `arc: [application: MyApp.Arc]`: the model is generated while you compile and embedded in your application's `priv`, and the explorer ships inside the package. It is served in development by default (`event_model:`), and `introspection` decides who may read it. See [Event model](Documentation/event-model.md).

### Changed

- **Names come from ids.** The structure and the event model name a command, event type, reactor and read model by its declared id (`use Cratis.Arc.Command, id: "register-author"`, an event type's `id:`, a reactor's `id:`) shown as `RegisterAuthor`, so renaming a module never renames the model. `use Cratis.Arc.ReadModel` takes an optional `id:` too. Choose the style with `display_names:` on the Arc application: `:pascal_case` (default), `:kebab_case`, `:as_declared` or a function of the id.
- **The event model connects slices.** A state view draws the events it consumes as events pointing at their source, an automation starts from the first event it handles, and ids of slice-level items no longer depend on the document, so the board links an event to the slice that owns it.
- **Arc requires Chronicle for Elixir 4.0**, where every module is under `Cratis.Chronicle`. `Chronicle.Events.EventType` is now `Cratis.Chronicle.Events.EventType`, `Chronicle.all/2` is `Cratis.Chronicle.all/2`, and so on. The analyzer rule `ARCE0004` follows the new names.
- **Every Arc module is under `Cratis.Arc`.** `Arc.Command` is now `Cratis.Arc.Command`, `Arc.ReadModel` is `Cratis.Arc.ReadModel`, `Arc.Test` is `Cratis.Arc.Test`, `Arc.MongoDB` is `Cratis.Arc.MongoDB`, and so on, including `Arc.execute/3`, `Arc.query/5` and `Arc.context/2`. Source files follow, under `lib/cratis/arc`.
- **A command declares its name as an option, like Chronicle.** `use Cratis.Arc.Command, id: "register-author"` replaces the `command "register-author"` declaration, in line with `use Cratis.Chronicle.Events.EventType, id: "..."`.

### Upgrading

- **Move to Chronicle for Elixir 4.0.** Require `{:cratis_chronicle, "~> 4.0"}` and replace `Chronicle.` with `Cratis.Chronicle.` in your code; see the upgrade page of Chronicle for Elixir.
- **Rename the modules and the command declaration.** Replace `Arc.` with `Cratis.Arc.` in `use`, `alias` and calls, and move `command "name"` into `use Cratis.Arc.Command, id: "name"`. Mix tasks, the `:arc_*` compilers, `config :cratis_arc` and the `arc:` project option keep their names.
- **New rules can produce new warnings.** Every release that adds a rule can make an existing build report findings it did not before, and `--warnings-as-errors` then fails it. Rules that find a likely bug (`ARCE0002`, `ARCE0005`) default to `:error`. Set a rule to `:warning` or `:off` under `config :cratis_arc, :analyzer, rules: [...]` while you fix the findings.
