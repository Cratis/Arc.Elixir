---
title: Commands
description: Declare a command's fields, rules and authorization, then decide in handle/2 and let Arc validate, authorize and record the events it returns.
---

A command is a request to change something. In Arc it is one module: the fields of the request, the rules that must hold, and the function that decides. Everything around that decision is Arc's job.

## Declare the request

`use Arc.Command` and a `schema` block define the struct. Each `field` has a name, a type and options.

```elixir
# From: Samples/phoenix/lib/library/authors/registration/rename_author.ex
defmodule Library.Authors.Registration.RenameAuthor do
  @moduledoc "Renames an author. Only editors may."

  use Arc.Command

  authorize roles: ["editor"]

  schema do
    field :id, Library.Authors.AuthorId, key: true, required: true
    field :name, :string, required: true, min_length: 2, max_length: 50
  end

  def handle(%__MODULE__{name: name}, _ctx),
    do: {:append, %Library.Authors.AuthorRenamed{name: name}}
end
```

`@moduledoc` is the command's documentation: its first line becomes the summary in `/.cratis/commands` and in the generated TypeScript.

### Field types

| Type | Wire | TypeScript |
| --- | --- | --- |
| `:string` | string | `string` |
| `:integer`, `:float` | number | `number` |
| `:boolean` | boolean | `boolean` |
| `:uuid` | string | `Guid` |
| `:date` | `YYYY-MM-DD` | `DateOnly` |
| `:datetime` | ISO 8601 | `Date` |
| `:map` | object | `object` |
| `{:list, type}` | array | `type[]` |
| a `Chronicle.Concept` module | the primitive it wraps | that primitive |
| a module that `use Arc.Schema` | object | a generated class |

Use a `Chronicle.Concept` for domain values such as an author id, so the type is declared once and the same value is what Chronicle records. Nested lists are not supported.

### Field options

| Option | Effect |
| --- | --- |
| `required: true` | Must be present; not nullable |
| `nullable: bool` | May be `nil`; defaults to `true` unless `required` |
| `key: true` | The event source of whatever the command appends |
| `default: value` | The struct default |
| `doc: "text"` | Documentation for the generated proxy |
| `min_length`, `max_length`, `email`, `matches` | String rules |
| `min`, `max`, `greater_than`, `less_than` | Number rules |

Rules are covered in [Validation](validation.md).

### Declarations

- `authorize roles: [...]`, `authorize :authenticated`, `authorize policy: :name`, `allow_anonymous()` — see [Authorization and identity](authorization-and-identity.md).
- `response type` — the type returned to the client, for the generated proxy, for example `response :string`.

## The callbacks

Only `handle/2` is required. The order is validate, `provide/2`, then `handle/2`, and each runs only if the previous steps passed.

| Callback | Use it to |
| --- | --- |
| `validate/2` | Add a cross-field or state-dependent rule. Return `:ok` or `{:error, result_or_results}` |
| `provide/2` | Load data once, after authorization and validation. Return `:ok`, `{:ok, map}` (merged into `ctx.provided`) or `{:error, results}` |
| `handle/2` | Decide |

## What handle returns

| Return | Meaning |
| --- | --- |
| `{:append, event}` | Record one event on the command's key |
| `{:append, [event, …]}` | Record several, in order |
| `{:append, events, response}` | Record, and return `response` to the client |
| `{:ok, response}` | Succeed without recording, for example a command that only calls a collaborator |
| `{:error, result_or_results}` | Reject with `Arc.Validation.error/3` results |

A command either records what happened or is rejected. Prefer `{:append, …}` for state changes; `{:ok, response}` is for the rare command with nothing to record.

To target an event source other than the key, wrap the event: `{:append, {other_id, event}}`. A command whose handler returns an event but declares no `key: true` field and gives no source id is rejected with a `frameworkFailure` result.

Events go to Chronicle with the principal as identity and the request's correlation id. Events for different sources append in separate calls, grouped in order; events for one source append atomically.

### When Chronicle says no

A constraint or concurrency rejection from Chronicle never reaches your code as an exception. Arc reports it as a validation result with reason `constraintViolation` (the constraint name in `reasonDetail`) or `concurrencyViolation`, so a client shows it like any other rejection. The `unique :name` constraint on the sample's `AuthorRegistered` event is how a duplicate name is refused.

## Run a command from code

`Arc.execute/3` runs the full pipeline, with the same checks as HTTP.

```elixir
result =
  Arc.execute(MyApp.Arc, %RegisterAuthor{id: Arc.new_id(), name: "Ada"}, principal: principal)

Arc.CommandResult.success?(result)
```

Pass `{RegisterAuthor, %{"id" => "…", "name" => "…"}}` instead of a struct to bind a wire map first. Options include `principal:`, `tenant:`, `correlation_id:`, `metadata:` and `validate_only: true`. The result is an `Arc.CommandResult`; `Arc.CommandResult.to_wire/1` is the envelope the HTTP host sends. Its shape is the contract with the frontend: see [Result envelopes](results.md).

## Exceptions

An exception in your code becomes a result with `exceptionMessages`. Outside development the message is replaced by a generic one and the stack trace is dropped; the full detail is always logged with the correlation id. Set `expose_exceptions: true` to include them. See [Configuration](configuration.md).

## Next steps

- [Validation](validation.md) for rules, severities and result reasons.
- [Testing](testing.md) to prove a command without a kernel.
