---
title: Validation
description: Declarative field rules, custom validate callbacks, result reasons and severities, and how Chronicle's constraint rejections reach the client.
---

Arc validates before it decides. Rules are declared once on the command and enforced on the server; with [generated proxies](react-proxies.md) the browser enforces the same rules before the request is sent.

## Declarative rules

Options on `field` are the rules. A request that breaks one is rejected with status 400, `isValid: false`, and a validation result naming the member. Nothing is recorded.

| Option | Server message | Client rule |
| --- | --- | --- |
| `required: true` | `'name' must not be empty.` | `notEmpty()` |
| `min_length: n` | `'name' must be at least n characters long.` | `minLength(n)` |
| `max_length: n` | `'name' must be at most n characters long.` | `maxLength(n)` |
| `email: true` | `'email' must be a valid email address.` | `emailAddress()` |
| `matches: "regex"` | `'code' has an invalid format.` | `matches(/regex/)` |
| `min: n` | `'age' must be greater than or equal to n.` | `greaterThanOrEqual(n)` |
| `max: n` | `'age' must be less than or equal to n.` | `lessThanOrEqual(n)` |
| `greater_than: n` | `'age' must be greater than n.` | `greaterThan(n)` |
| `less_than: n` | `'age' must be less than n.` | `lessThan(n)` |

String rules apply to `:string` fields and number rules to `:integer` and `:float`; the generated validators include only the rules their TypeScript rule supports. Member names in messages are the `camelCase` wire names. Messages are developer-facing and may change; branch on `reason`, not on text.

## Custom rules

Define `validate/2` for anything declarations cannot say. It runs after the declarative rules and receives the bound command.

```elixir
# From: Samples/phoenix/lib/library/authors/registration/register_author.ex
  def validate(%__MODULE__{name: name}, _ctx) when name in ["admin", "root"],
    do: {:error, Arc.Validation.error("That name is reserved.", [:name])}

  def validate(_command, _ctx), do: :ok
```

`Arc.Validation.error(message, members, opts)` builds a result; `members` are field atoms. Options are `severity:`, `state:`, `reason:` and `reason_detail:`. `Arc.Validation.warning/3` builds a warning.

## Results, reasons and severities

A result carries `severity`, `message`, `members`, `state`, `reason` and `reasonDetail`. `reason` says what composed it and is an open set; clients must tolerate new values.

| Reason | Meaning |
| --- | --- |
| `rule` | An application rule rejected the input. Show the message |
| `malformedRequest` | The request could not be bound: a wrong type, a missing required argument, a body that is not JSON |
| `constraintViolation` | A Chronicle constraint rejected the append; the constraint is in `reasonDetail` |
| `concurrencyViolation` | The event source changed since it was read; re-read and retry |
| `frameworkFailure` | Arc could not complete the command, for example no event source id, or a failed append |

Severities are `unknown` (0), `information` (1), `warning` (2) and `error` (3).

### Tolerating warnings

A caller can tolerate non-blocking results by sending the numeric `X-Allowed-Severity` header. Results at or below that severity are dropped before the envelope is built; what remains blocks. Arc caps the header at `Warning`, so a client cannot tolerate errors, and it ignores a non-numeric or out-of-range value. Without the header every result blocks.

## Validate without executing

`POST <command route>/validate` runs authorization and validation and stops. The generated command's `validate()` calls it. In LiveView, `validate_form/3` does the same; see [LiveView](live-view.md).

## Next steps

- [Authorization and identity](authorization-and-identity.md) runs before validation.
- [Commands](commands.md#when-chronicle-says-no) covers constraint and concurrency results.
