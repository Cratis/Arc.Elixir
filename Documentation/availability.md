---
title: Availability
description: Declare which parts of an application exist for which audiences, suspend parts at run time, and let the frontend hide what the caller cannot use, with the same model and manifest as Arc for .NET.
---

Availability decides whether a part of the application exists for the caller in front of you. A part is a command or a query; parts are grouped in modules, features and slices. It is the same model as Arc for .NET and Screenplay: audiences, blocks, gates and suspension, written in the same words.

It is one gate and it runs **first**: before binding, `Cratis.Arc.Filter`, authorization and validation. There is no second gating mechanism.

| Decision | Result |
| --- | --- |
| Available | The request continues to authorization and validation. |
| Not available, or unknown | Not authorized, `authorizationFailureReason` `NotAvailable`, HTTP `403`. |
| Suspended | Not authorized, reason `Suspended`, HTTP `403`. |
| The decision could not be made | A retryable error: `isRetryable` is `true`, the result stays authorized, HTTP `503`. |

An unavailable and an unknown decision are reported identically; which gate closed it is logged at debug level and never sent. A store that is down is never reported as a denial.

## The vocabulary

Name a definition in the configuration:

```elixir
config :my_app, MyApp.Arc,
  availability: [
    definition: MyApp.Availability,
    audience_source: MyApp.AudienceSource,
    suspension_source: MyApp.SuspensionSource,
    pubsub: MyApp.PubSub
  ]
```

```elixir
defmodule MyApp.Availability do
  use Cratis.Arc.Availability.Definition

  audience "Plus", "Customers on the Plus package"
  audience "Admin", "Operators"

  block "Paid", "Sold with Plus", for: ["Plus", "Admin"]

  # a gate on a module, a feature or a slice: everything below the namespace
  scope "MyApp.Fleet", with: "Paid"

  # a context value: read lazily, once per request
  value "vessel", MyApp.VesselValue
end
```

## Declaring a gate

A command, a read model, or one query declares its gate with the words of the language. Every line holds.

```elixir
defmodule MyApp.Fleet.Vessels.DockVessel do
  use Cratis.Arc.Command
  available for: ["Plus", "Admin"], not: "Preview", with: "Reported"
  available when: MyApp.HasPaidInvoice
end
```

* `for:` an audience, or a list of which one is enough
* `not:` an audience, or a list of which none may be held
* `with:` a named block
* `when:` a condition: restricted data from `Cratis.Arc.Availability.Condition`, shared with other languages, or a module implementing that behaviour for anything else

```elixir
available when: Cratis.Arc.Availability.Condition.equal("vessel.package", "Plus")
available when: Cratis.Arc.Availability.Condition.equal("arguments.vesselId", "v-17")
```

On a read model `available` gates every query of the module; `@query available: [...]` gates one query. Module, feature and slice come from `Cratis.Arc.Descriptor.slice_location/2`, the same as in generated proxies.

A condition reads `tenant`, `identity.user`, `arguments.<name>` (what the part is about, by its wire name, camelCase) and `<name>.<path>` of a provided value. The tenant and the identity always come from the server; arguments never replace them.

## Three values

An expression is available, unavailable or unknown. Only available opens a gate. An absent value is unknown, for every operator, including not-equal; so is an audience that could not be decided. A value is read at most once per request. `Cratis.Arc.Availability.Engine` is a port of the .NET engine and passes the shared conformance cases.

## Audiences: granted and withdrawn

Implement `Cratis.Arc.Availability.AudienceSource` over your storage: `grants(subject)` returns the names of the audiences the tenant and user hold. A grant for an audience the definition does not declare never matches. `Cratis.Arc.Availability.Memory` is a complete source for specifications and samples (`grant/2`, `withdraw/2`).

## Parts: suspended and resumed

Implement `Cratis.Arc.Availability.SuspensionSource`: `suspended/0` returns paths. A path is a module (`"Fleet"`), a feature (`"Fleet/Vessels"`), a slice (`"Fleet/Vessels/Dock"`), or the full name of a part (a command's module, a query as `Module.QueryName`; the module name suspends all its queries). A suspension is decided before any gate. `Memory.suspend/1` and `Memory.resume/1` do it in memory.

When a source changes, call `Cratis.Arc.Availability.changed/1`. Open sessions decide again, on every node when `:pubsub` (a `Phoenix.PubSub`) is configured.

## The client: `/.cratis/availability`

An observable query that lists what is not available to the caller:

```json
{ "unavailable": [ { "name": "MyApp.Fleet.Vessels.DockVessel", "module": "Fleet", "feature": "Vessels", "slice": "Dock", "reason": "NotAvailable" } ] }
```

It emits the current answer, and again whenever audiences or suspensions change. `?part=<name>&arguments=<json>` asks about one part and the data it is about. Generated proxies carry `static readonly part`, so a client knows what to ask about. A decision that cannot be made is a retryable error for the query, never a list.

## LiveView

```heex
<Cratis.Arc.LiveView.Availability.available socket={@socket} version={@arc_availability} command={MyApp.Fleet.Vessels.DockVessel}>
  <button phx-click="dock">Dock</button>
</Cratis.Arc.LiveView.Availability.available>
```

The component asks the same gate (`Cratis.Arc.LiveView.available?/3`). Hiding is presentation; the server still refuses.

## The manifest

`Cratis.Arc.Availability.Manifest.build/1` (and `to_json/1`) writes the `cratis-availability-manifest` file, version 1, that every Arc implementation shares; `decode/1` reads one, `decide/3` decides a part of it. The shared vectors of Cratis/Arc run in `test/cratis/arc/availability_conformance_test.exs` against pinned copies in `test/support/availability`.
