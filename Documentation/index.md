---
title: Arc for Elixir
description: Arc for Elixir is a CQRS application framework for Phoenix and Plug that turns plain modules into commands, queries and an HTTP API on Cratis Chronicle.
---

Arc for Elixir is a CQRS application framework for Phoenix and Plug applications. You write commands and queries as plain modules, and Arc serves them: validated, authorized, recorded in [Cratis Chronicle](https://github.com/Cratis/Chronicle), and reachable from React, LiveView or any HTTP client.

## Without Arc, with Arc

Without a framework, every feature repeats the same plumbing. A controller binds and validates params, checks who is calling, calls a context function, shapes an error response, and a separate channel or PubSub topic pushes updates to the browser. The TypeScript client that calls it is written by hand and drifts.

With Arc, the feature is two modules. A command declares its fields and decides; a read model declares its queries. Binding, validation, authorization, the response envelope, live updates and, if you use React, the typed client are the framework's job.

```elixir
# From: Samples/phoenix/lib/library/authors/registration/register_author.ex
defmodule Library.Authors.Registration.RegisterAuthor do
  @moduledoc "Registers a new author."

  use Arc.Command

  schema do
    field :id, Library.Authors.AuthorId, key: true, required: true
    field :name, :string, required: true, min_length: 2, max_length: 50
  end

  # A cross-field rule beyond the declarative ones above.
  def validate(%__MODULE__{name: name}, _ctx) when name in ["admin", "root"],
    do: {:error, Arc.Validation.error("That name is reserved.", [:name])}

  def validate(_command, _ctx), do: :ok

  # Decide, and return what happened. Arc appends the event to the command's key.
  def handle(%__MODULE__{name: name}, _ctx),
    do: {:append, %Library.Authors.AuthorRegistered{name: name}}
end
```

## What you get

- **Commands and queries as modules.** Fields, rules and authorization are declarations; `handle/2` is the only logic.
- **The Arc HTTP contract on Plug.** `@cratis/arc`, `@cratis/arc.react` and Cratis Components work against it unchanged, as a single-page application.
- **LiveView, in process.** The same commands and queries, called without an HTTP hop, with forms that show the pipeline's errors on the right field.
- **Observable queries.** A query that re-runs when Chronicle changes a read model and pushes the result over WebSocket or Server-Sent Events.
- **Opt-in TypeScript proxies.** Only if you build a React frontend: `mix arc.gen.proxies` generates typed commands and queries, with the same validation rules as the server.
- **Identity.** The signed-in user, their roles and typed application details, served to React from `/.cratis/me` and to LiveView in process, with development users for tools such as Lens, the signed forwarded-identity envelope and on-behalf-of, as in Arc on .NET.
- **The same result envelopes.** Commands and queries answer with exactly the shapes the other Arc implementations do, so the frontend packages work unchanged. See [Result envelopes](results.md).
- **Chronicle underneath.** Returned events are appended to the event store with the caller's identity and correlation.

Arc for Elixir works with Chronicle only. It does not persist state any other way.

## Where to go next

- New here? [Get started](get-started.md) builds an authors feature end to end.
- Want the model first? [How Arc works](concepts.md) explains artifacts, the pipeline and routes.
- Building a React frontend? [React and generated proxies](react-proxies.md).
- Using LiveView? [LiveView](live-view.md).
- Contributing? [Build and release](contributing/build-and-release.md).

## Related

- The language-neutral [Arc HTTP contract](/arc/http-contract/) that this implementation follows.
- [Chronicle Elixir client](/chronicle/clients/elixir/), which Arc uses to record events.
