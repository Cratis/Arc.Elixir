---
title: Event model
description: See your application's commands, events, read models and reactions drawn as an event model, from the explorer at /.cratis/event-model that Arc generates while you compile.
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
