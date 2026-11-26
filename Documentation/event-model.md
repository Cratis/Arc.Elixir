---
title: Event model
description: Enable the Arc event model explorer in Elixir to see how your application's commands, events, read models and reactions connect across slices.
---

Arc draws what your application does as an **event model**: the slices of each feature with the commands that start them, the events they record, the read models and queries that show the result, and the reactions that follow. It is the same explorer the C# Arc serves, at the same address, `/.cratis/event-model`, and it works from the code you already wrote.

## Switch it on

Add the compiler and name the Arc application in `mix.exs`:

```elixir
def project do
  [
    # ...
    compilers: Mix.compilers() ++ [:arc_event_model],
    arc: [application: MyApp.Arc]
  ]
end
```

Run the application and open `/.cratis/event-model/`. Arc serves it from `Cratis.Arc.Plug`, so the application must mount it, and `Cratis.Arc.Plug` has to see the request before anything that only accepts HTML:

```elixir
plug Cratis.Arc.Plug, application: MyApp.Arc
```

The explorer is served in development. Elsewhere set `event_model: true` on the Arc application. It reveals the whole application model, so who may read it follows the `introspection` option of the application: `:authenticated` by default, `:anonymous`, or `false` to remove it.

## What it shows

The documents are the application, one per module and one per feature, in the same arrangement Arc uses for routes and proxy folders: the namespace after `segments_to_skip`, split into module, feature and slice.

| A slice with | Is a | And holds |
| --- | --- | --- |
| a command | state change | the command, and the events it appends |
| a read model, reducer or projection | state view | the read model, its queries, and the events it consumes |
| only a reactor | automation | the reaction, the events it handles and the ones it emits |

The **Source** tab shows the same model as [Cratis Screenplay](https://github.com/Cratis/Screenplay) text.

## The events of a command

A command returns the events it appends, so Arc reads them from the compiled module: the event types it builds. A reactor's emitted events are found the same way, and the events it handles come from `@handles`. A command that builds its events somewhere else, in another module, shows only what it builds itself.

## Names

The model names a command, an event type, a reactor and a read model by the `id:` it declares, not by its module, so renaming a module never renames the model. The kebab-case id is shown in PascalCase (`"register-author"` is `RegisterAuthor`). Choose another style with `display_names:` on the Arc application: `:kebab_case`, `:as_declared` or a function of the id. `/.cratis/structure` follows the same setting. A command or read model without an `id:` keeps the last segment of its module name.

A state view lists the events it consumes and an automation starts from the first event it handles, each pointing at the event of the slice that owns it, so the board connects the slices.

## Sub-features, order and checks

Folders below the module are features, and a feature inside a feature is a sub-feature: `Prism.Access.ApiCredentials.Secrets.RotatingSecrets` is the slice `RotatingSecrets` of the sub-feature `Secrets` of `ApiCredentials`. The board nests them and the Screenplay source nests `feature` inside `feature`.

The model reads in order: a fact is drawn before whatever uses it. A view or an automation comes after the slices that produce the events it consumes; features follow the same order, and a feature's own slices come before its sub-features, so a slice that uses events of a sub-feature belongs in a sub-feature of its own.

The compiler checks the model and warns about what is missing: a state change without a command or events, a view without a read model or consumed events (name events read some other way with `consumes:` on the read model), an automation that reacts to or records nothing, an event no slice produces, a fact used before it is produced. Set `event_model_strict: true` in the project's `arc:` options to make them errors.

## Embedded at build time

The model is not worked out when a request arrives. The compiler writes it to `priv/cratis/event_model/` of your application: a `catalog.json`, and for each document a `*.model.json` (the document [`@cratis/event-models`](https://www.npmjs.com/package/@cratis/event-models) draws) and a `*.screenplay`. It is part of every release, the way the C# build embeds it in the assembly, and nothing is analysed in production. The explorer itself ships inside the `cratis_arc` package.

Add `event_model_apps: [:other_app]` to the Arc application to show the models embedded by other OTP applications of the same release.

## Routes

| Route | Answers |
| --- | --- |
| `/.cratis/event-model/` | the explorer |
| `/.cratis/event-model/hierarchy` | the projects and their documents |
| `/.cratis/event-model/documents/{project}/{document}/model` | the board model |
| `/.cratis/event-model/documents/{project}/{document}/source` | the Screenplay source |
| `/.cratis/event-model/assets/*` | the explorer's files |
