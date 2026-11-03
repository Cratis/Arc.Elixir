---
title: Testing
description: Test commands, queries, the HTTP host and LiveView against Chronicle's in-memory kernel with Arc.Test, using the real pipelines and no mocks.
---

Test what the application does, not how it is wired. `Arc.Test` runs the real pipeline, with real binding, validation, authorization and appends, against Chronicle's in-memory kernel. Nothing is mocked.

## A command test

```elixir
# From: Samples/phoenix/test/library/authors_test.exs
      test "a name that is too short is rejected before anything is recorded", %{arc: arc} do
        result = Arc.Test.execute(arc, {RegisterAuthor, %{"id" => Arc.new_id(), "name" => "A"}})

        Arc.Test.assert_invalid(result, :name)
        Arc.Test.refute_appended(arc, AuthorRegistered)
      end
```

`use Arc.Test.Case` starts a Chronicle test client for each test and puts an `Arc.Test.Scenario` in the context as `:arc`:

```elixir
use Arc.Test.Case,
  application: Library.Arc,
  event_types: [Library.Authors.AuthorRegistered, Library.Authors.AuthorRenamed]
```

Every option of `Chronicle.Testing.start_supervised_client/1` is accepted (`event_types`, `reactors`, `reducers`, `constraints`). Each test has its own kernel, so `async: true` is safe.

## Functions

| Function | Use |
| --- | --- |
| `Arc.Test.execute/3` | Execute a command struct or `{module, wire_map}`; options as for `Arc.execute/3`, for example `principal:` |
| `Arc.Test.query/5` | Execute a query |
| `Arc.Test.principal/2` | An authenticated principal with roles |
| `assert_success/1`, `assert_invalid/2`, `assert_forbidden/1` | Assert on a result |
| `assert_appended/3`, `refute_appended/3` | Assert on Chronicle's events; accepts an event module, struct or function, and `event_source_id:` |
| `wait_for_observers/1` | Wait for in-memory reducers and reactors |

## Through HTTP or LiveView

The HTTP host and LiveView use the application's own configuration, so point it at the test client with `configure: true`. This is global, so these tests are not `async`.

```elixir
use Arc.Test.Case,
  application: Library.Arc,
  configure: true,
  event_types: [Library.Authors.AuthorRegistered]
```

Then drive the endpoint with `Plug.Test` and `Phoenix.LiveViewTest` as usual. For observable queries add `observable: true` to start the application's supervisor, unless your application already starts it in its supervision tree (the Phoenix sample does).

`Phoenix.LiveViewTest` needs `{:lazy_html, ">= 0.1.0", only: :test}` in your dependencies.

## What the in-memory kernel cannot do

Chronicle's test kernel runs appends, constraints and concurrency checks for real, and runs reactors and reducers synchronously after each append. It has no read-model query surface, so `Chronicle.all/2` and `Chronicle.read_model/3` do not work against it. That has two consequences:

- Queries that read Chronicle read models cannot be exercised end to end in these tests. Test the decision (the command) and the data shaping separately, and verify queries against a development kernel.
- A LiveView page that lists a read model renders an empty list in tests. The Phoenix sample says so and tests the form, validation and recording instead.

For a query you can test without a kernel, keep the data access in a function you can call from the query and from the test.

## Next steps

- [Samples](samples.md) show every kind of test in context.
