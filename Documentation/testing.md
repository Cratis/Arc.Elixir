---
title: Testing
description: Test commands, queries, the HTTP host and LiveView against Chronicle's in-memory kernel with Cratis.Arc.Test, using the real pipelines and no mocks.
---

Test what the application does, not how it is wired. `Cratis.Arc.Test` runs the real pipeline, with real binding, validation, authorization and appends, against Chronicle's in-memory kernel. Nothing is mocked.

## A command test

```elixir
# From: Samples/phoenix/test/library/authors_test.exs
      test "a name that is too short is rejected before anything is recorded", %{arc: arc} do
        result = Arc.Test.execute(arc, {RegisterAuthor, %{"id" => Arc.new_id(), "name" => "A"}})

        Arc.Test.assert_invalid(result, :name)
        Arc.Test.refute_appended(arc, AuthorRegistered)
      end
```

`use Cratis.Arc.Test.Case` starts a Chronicle test client for each test and puts a `Cratis.Arc.Test.Scenario` in the context as `:arc`:

```elixir
use Cratis.Arc.Test.Case,
  application: Library.Arc,
  event_types: [Library.Authors.AuthorRegistered, Library.Authors.AuthorRenamed]
```

Every option of `Cratis.Chronicle.Testing.start_supervised_client/1` is accepted (`event_types`, `reactors`, `reducers`, `constraints`). Each test has its own kernel, so `async: true` is safe.

## Scenarios

A **scenario** states one behavior in the shape of a Specification: facts are given, the behavior happens **once**, and each `test` is one `should_*` expectation. `Cratis.Arc.Test.CommandScenario` and `Cratis.Arc.Test.QueryScenario` are the Elixir counterparts of `CommandScenario<T>` and `QueryScenario<T>`; Chronicle has `EventScenario`, `ReadModelScenario` and `ReactorScenario` for events, read models and reactors.

```elixir
defmodule MyApp.Authors.ForRegisterAuthor.WhenRegistering.WithAValidName do
  use Cratis.Arc.Test.CommandScenario,
    application: MyApp.Arc,
    event_types: [MyApp.Authors.AuthorRegistered]

  alias MyApp.Authors.{AuthorRegistered, RegisterAuthor}

  setup_all %{scenario: scenario} do
    scenario =
      scenario
      |> given_events("ada", %AuthorRegistered{name: "Ada"})
      |> execute(%RegisterAuthor{id: "grace", name: "Grace"}, as: principal("tester", ["maintainer"]))

    %{scenario: scenario}
  end

  test "should be successful", %{scenario: scenario}, do: should_be_successful(scenario)

  test "should append the author as registered", %{scenario: scenario} do
    should_have_appended(scenario, %AuthorRegistered{name: "Grace"}, event_source_id: "grace")
  end
end
```

`use` starts the kernel once for the module (`lifecycle: :shared`, the default, like the Specification's shared lifecycle) and puts the scenario in the context as `:scenario`; with `lifecycle: :per_test` it starts one per test, and you write `setup` instead of `setup_all`. A scenario is an immutable value: **given** and **because** functions (`given_events/3`, `execute/3`, `query/5`) return the next scenario, and **should** functions return the scenario they checked, so they chain.

| Should | Checks |
| --- | --- |
| `should_be_successful/1`, `should_not_be_successful/1` | the result is authorized, valid and free of exceptions, or is not |
| `should_not_be_authorized/1` | the caller was refused before anything ran |
| `should_have_validation_errors/1,2` | a validation failure, optionally for a member or with a message |
| `should_have_exception/1,2` | the command raised, optionally with a message |
| `should_have_constraint_violation/1,2`, `should_have_concurrency_violation/1` | Chronicle refused the append |
| `should_respond_with/2` | the command's response (a predicate, a sub-map or a value) |
| `should_have_appended/2,3`, `should_not_have_appended/2,3` | an event (an exact struct, an event type module or a predicate) was or was not appended **by the command**, not given |
| `should_have_appended_exactly/2`, `should_not_have_appended_any_events/1` | the events appended, in order, or none |
| `should_return/2`, `should_return_items/2`, `should_return_nothing/1` | what a query returned |

## Should

`Cratis.Arc.Test.Should` is the Elixir counterpart of the `Should` extensions of Cratis.Specifications. The functions take the value first, read as a sentence, and return it, so they pipe and chain:

```elixir
import Cratis.Arc.Test.Should

result.response.id |> should_not_be_nil() |> should_be_of_type(:binary)
events |> should_contain_only([AuthorRegistered, NameChanged])
response |> should_match(%{id: _, secret: %Secret{}})
```

It has `should_equal/2`, `should_not_equal/2`, `should_be_true/1`, `should_be_false/1`, `should_be_nil/1`, `should_not_be_nil/1`, `should_be_empty/1`, `should_not_be_empty/1`, `should_contain/2`, `should_not_contain/2`, `should_contain_only/2`, `should_contain_single_item/1`, `should_each_conform_to/2`, `should_start_with/2`, `should_end_with/2`, `should_match/2` (a macro: `import` or `require` the module), `should_satisfy/2`, `should_be_of_type/2`, the four `should_be_greater_than`/`less_than` comparisons and `should_be_in_range/2`, `should_not_be_in_range/2`. A failure is an `ExUnit.AssertionError` with both values, so it reads in the ExUnit output like any other.

## Functions

| Function | Use |
| --- | --- |
| `Cratis.Arc.Test.execute/3` | Execute a command struct or `{module, wire_map}`; options as for `Cratis.Arc.execute/3`, for example `principal:` |
| `Cratis.Arc.Test.query/5` | Execute a query |
| `Cratis.Arc.Test.principal/2` | An authenticated principal with roles |
| `assert_success/1`, `assert_invalid/2`, `assert_forbidden/1` | Assert on a result |
| `assert_appended/3`, `refute_appended/3` | Assert on Chronicle's events; accepts an event module, struct or function, and `event_source_id:` |
| `wait_for_observers/1` | Wait for in-memory reducers and reactors |

## Through HTTP or LiveView

The HTTP host and LiveView use the application's own configuration, so point it at the test client with `configure: true`. This is global, so these tests are not `async`.

```elixir
use Cratis.Arc.Test.Case,
  application: Library.Arc,
  configure: true,
  event_types: [Library.Authors.AuthorRegistered]
```

Then drive the endpoint with `Plug.Test` and `Phoenix.LiveViewTest` as usual. For observable queries add `observable: true` to start the application's supervisor, unless your application already starts it in its supervision tree (the Phoenix sample does).

`Phoenix.LiveViewTest` needs `{:lazy_html, ">= 0.1.0", only: :test}` in your dependencies.

## Where specs live

Name a spec for what it specifies, not with a `_test` suffix: `for_<unit>/when_<behavior>/<and|with|without>_<condition>.exs`, beside the code. The folders already say it is a spec, as in the C# and TypeScript specs. They are scripts, so a release never contains them. Point `mix test` at the folders:

```elixir
test_paths: ["lib"],
test_load_filters: [&(String.contains?(&1, "/for_") and not String.contains?(&1, "/given/"))],
```

`test_load_filters` replaces the default `*_test.exs` pattern. Shared contexts go in `for_<unit>/given/` and a spec loads them with `Code.require_file/2`.

## What the in-memory kernel cannot do

Chronicle's test kernel runs appends, constraints and concurrency checks for real, and runs reactors and reducers synchronously after each append. It has no read-model query surface, so `Cratis.Chronicle.all/2` and `Cratis.Chronicle.read_model/3` do not work against it. That has two consequences:

- Queries that read Chronicle read models cannot be exercised end to end in these tests. Test the decision (the command) and the data shaping separately, and verify queries against a development kernel.
- A LiveView page that lists a read model renders an empty list in tests. The Phoenix sample says so and tests the form, validation and recording instead.

For a query you can test without a kernel, keep the data access in a function you can call from the query and from the test.

## Next steps

- [Samples](samples.md) show every kind of test in context.
