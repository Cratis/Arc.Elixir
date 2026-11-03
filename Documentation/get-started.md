---
title: Get started with Arc for Elixir
description: Add cratis_arc to a Phoenix project, define a command and a query, and call them from the browser, from LiveView, and from a test, with Chronicle underneath.
---

In this guide you build an authors feature: register an author, list authors live, and see the same rules apply over HTTP, in LiveView and in a test. By the end, posting a command to your Phoenix app records an event in Chronicle and the list updates without a refresh.

The finished code is in the [Phoenix sample](https://github.com/Cratis/Arc.Elixir/tree/main/Samples/phoenix); each step below is excerpted from it.

## Prerequisites

- Elixir 1.18 or later and a Phoenix 1.7+ project (a plain Plug application works too; see [Plug](hosting/plug.md)).
- Docker, for a local Chronicle kernel.
- Familiarity with the [Chronicle Elixir client](/chronicle/clients/elixir/); Arc builds on it.

## Start Chronicle

```shell
docker pull cratis/chronicle:latest-development
docker run -d --name chronicle \
  -p 127.0.0.1:35000:35000 \
  -p 127.0.0.1:27017:27017 \
  cratis/chronicle:latest-development
```

## Install

Add Arc to `deps` in `mix.exs`. It brings `cratis_chronicle` with it.

```elixir
defp deps do
  [
    {:cratis_arc, "~> 0.1"}
  ]
end
```

## Define the events and the read model

Events are Chronicle event types. The read model is a Chronicle projection: Chronicle keeps it current from the events, so Arc never writes it.

```elixir
# From: Samples/phoenix/lib/library/authors/author_registered.ex
defmodule Library.Authors.AuthorRegistered do
  @moduledoc "An author was registered."

  use Chronicle.Events.EventType, id: "library-author-registered"

  defstruct name: ""

  # A store-level rule: no two authors may share a name. Chronicle enforces it at append time,
  # and Arc reports a violation to the client as a `constraintViolation` validation result.
  unique :name, message: "An author with that name is already registered."
end
```

```elixir
# From: Samples/phoenix/lib/library/authors/author.ex
defmodule Library.Authors.Author do
  @moduledoc "An author as the application shows it. Chronicle keeps it current from the events."

  use Chronicle.ReadModels.ReadModel

  defstruct id: "", name: ""

  from Library.Authors.AuthorRegistered, set: [id: :event_source_id, name: :name]
  from Library.Authors.AuthorRenamed, set: [name: :name]
end
```

## Define a command

The command at the top of the [overview](index.md) is the whole write side. Three things to notice:

- `schema` declares the request. The `key: true` field is the event source: whatever `handle/2` appends goes to that id.
- Declarative options (`required`, `min_length`, `max_length`) are validated by the server and, with proxies, by the browser.
- `handle/2` returns `{:append, event}`. It does not call `Chronicle.append` itself.

## Define a query

A read model module holds the queries over one model. A query is a function that takes `(args, ctx)`, annotated with `@query` or `@observe`.

```elixir
# From: Samples/phoenix/lib/library/authors/listing/authors.ex
      @doc "All authors."
      @query many: true
      def all_authors(_args, ctx), do: Chronicle.all(Author, ctx.chronicle)
```

`ctx.chronicle` carries the options Arc was configured with, for example which Chronicle client to use. Pass it on to Chronicle calls.

## Start Arc

Define the application module and add it to the supervision tree after the Chronicle client.

```elixir
# From: Samples/phoenix/lib/library/arc.ex
    defmodule Library.Arc do
      @moduledoc "The Arc application: discovers the commands and read models under `Library`."

      use Arc.Application, otp_app: :library
    end
```

Arc scans `:library` for modules that declare commands or read models. There is no registration list to keep in sync.

## Serve it

Add `Arc.Plug` to the endpoint, before the router. Requests that are not Arc routes pass through.

```elixir
      plug Arc.Plug, application: Library.Arc
```

Now run the app and post a command. Routes come from module names: with `segments_to_skip: 1`, `Library.Authors.Registration.RegisterAuthor` is `POST /api/authors/registration/register-author`.

```shell
mix phx.server

curl -s -X POST localhost:4000/api/authors/registration/register-author \
  -H 'content-type: application/json' \
  -d '{"id":"7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e","name":"Ada Lovelace"}'
```

```json
{"correlationId":"…","isAuthorized":true,"isValid":true,"isSuccess":true,"hasExceptions":false,"validationResults":[],"exceptionMessages":[],"exceptionStackTrace":"","authorizationFailureReason":""}
```

Send `"name":"A"` and the same call returns status 400 with a validation result for `name`, and nothing is recorded. That envelope is the [Arc HTTP contract](/arc/http-contract/), the same one the C# and Kotlin implementations serve.

Read the list back:

```shell
curl -s localhost:4000/api/authors/listing/all-authors
```

Chronicle projects asynchronously, so the author appears a moment after the command returns.

## Use it from LiveView

LiveView calls the same modules in process. The page keeps the list current and shows validation errors as you type.

```elixir
      def mount(_params, session, socket) do
        # The signed-in user lives in the session; Arc reads the principal from the socket on every call.
        socket = if user = session["user"], do: assign(socket, :current_user, user), else: socket

        {:ok,
         socket
         |> assign(:notice, nil)
         |> assign_observable(:authors, Authors, :live_authors)
         |> new_form()}
      end
```

[LiveView](live-view.md) explains the rest.

## Test it

`Arc.Test` runs the real pipeline against Chronicle's in-memory kernel, so you test behavior without a running kernel.

```elixir
# From: Samples/phoenix/test/library/authors_test.exs
      test "registering an author records AuthorRegistered on the author's event source", %{arc: arc} do
        id = Arc.new_id()

        result = Arc.Test.execute(arc, {RegisterAuthor, %{"id" => id, "name" => "Ada Lovelace"}})

        Arc.Test.assert_success(result)
        Arc.Test.assert_appended(arc, %AuthorRegistered{name: "Ada Lovelace"}, event_source_id: id)
      end
```

## Recap

You declared a command and a query as modules, started `Library.Arc`, mounted `Arc.Plug`, and got an HTTP API, a LiveView page and tests from the same declarations. Nothing between the request and the event store is hand-written.

## Next steps

- [How Arc works](concepts.md) explains discovery, the pipeline and the context.
- Building a React app? [React and generated proxies](react-proxies.md) is opt-in and adds typed clients.
- [Commands](commands.md) and [Queries](queries.md) cover every option.
