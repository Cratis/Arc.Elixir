---
title: Result envelopes
description: The exact command and query result shapes Arc for Elixir returns to the frontend - the contract the React packages and every Arc client depend on.
---

Every command and query answers with a result envelope. The frontend packages parse these shapes, so they are the contract between the backend and the client. Arc for Elixir keeps them identical to the other Arc implementations; the `Arc.EnvelopeTest` specs pin each field name and type, so a change is always deliberate.

The Elixir structs are `Arc.CommandResult` and `Arc.QueryResult`. `to_wire/1` on each produces the JSON body, and `status/1` the HTTP status. Field names on the wire are `camelCase`.

## Command result

| Field | Type | Notes |
| --- | --- | --- |
| `correlationId` | UUID string | Always present |
| `isAuthorized` | boolean | The authorization outcome |
| `validationResults` | array | Always present, empty when valid |
| `exceptionMessages` | array of string | Always present. Outside development the detail is replaced by a generic message |
| `exceptionStackTrace` | string | Empty when redacted or absent |
| `authorizationFailureReason` | string | Empty when authorized |
| `isValid` | boolean | `true` only when `validationResults` is empty, whatever the severity |
| `hasExceptions` | boolean | `true` when `exceptionMessages` is not empty |
| `isSuccess` | boolean | Authorized, valid and without exceptions |
| `response` | any | Present only on success and only when the command returned one |

`isValid`, `hasExceptions` and `isSuccess` are derived, never independent. A failed command never carries a `response`, so a client cannot receive a value alongside a failure it must not act on.

## Query result

| Field | Type | Notes |
| --- | --- | --- |
| `correlationId` | UUID string | Always present |
| `data` | any | The query's data; omitted when null, and absent on any failure |
| `isReady` | boolean | `false` for an observable query that has not produced a result |
| `isAuthorized` | boolean | The authorization outcome |
| `validationResults` | array | Always present |
| `exceptionMessages` | array of string | Always present |
| `exceptionStackTrace` | string | Empty when redacted or absent |
| `paging` | object | Always present: `page` (zero-based), `size`, `totalItems`, `totalPages` |
| `isValid`, `hasExceptions` | boolean | As for commands |
| `isSuccess` | boolean | Ready, authorized, valid and without exceptions |

`totalPages` is `0` when `size` is `0`, otherwise `totalItems` divided by `size`, rounded up. A query that is not paged reports `size: 0` and the number of items in `totalItems`. The delta `changeSet` of the contract is not produced; see [Limits and gaps](limits-and-gaps.md).

## Validation result

| Field | Type | Notes |
| --- | --- | --- |
| `severity` | number | `0` unknown, `1` information, `2` warning, `3` error |
| `message` | string | Developer-facing; free to change |
| `members` | array of string | The `camelCase` member names |
| `reason` | string | An open set; defaults to `rule` |
| `state` | any | Present only when set |
| `reasonDetail` | string | Present only when set |

See [Validation](validation.md#results-reasons-and-severities) for the reasons.

## Status codes

The HTTP status is selected in a fixed order, which matters when a result carries more than one kind of failure.

| Order | Condition | Command | Query |
| --- | --- | --- | --- |
| 1 | Success | 200 | 200 |
| 2 | Not authorized | 403 | 403 |
| 3 | Validation failure | 400 | 400 |
| 4 | Not ready | | 202 |
| 5 | Exception | 500 | 500 |

An authentication handler that fails the request answers 401 before any envelope is built.

## Identity

`GET /.cratis/me` has its own shape: `{id, name, isAuthenticated, isAuthorized, roles, details}`, with empty 401 and 403 responses. See [Authorization and identity](authorization-and-identity.md#identity-for-the-frontend).

## Next steps

- [Commands](commands.md) and [Queries](queries.md) say how results are produced.
- The language-neutral [Arc HTTP contract](/arc/http-contract/) is the authority these shapes follow.
