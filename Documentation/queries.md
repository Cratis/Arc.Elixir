---
title: Queries and read models
description: Declare queries over a Chronicle read model with @query and @observe, take typed parameters, page and sort lists, and push live results to clients.
---

A query reads. In Arc it is a function on a read model module, with typed parameters, optional paging and sorting, and, if you want it, live updates.

## A read model module

`use Arc.ReadModel, model: …` names the struct the queries return, normally a [Chronicle read model](/chronicle/clients/elixir/). Annotate functions with `@query` or `@observe`. Each takes `(args, ctx)` and returns `{:ok, value}` or `{:error, results}`.

```elixir
# From: Samples/phoenix/lib/library/authors/listing/authors.ex
defmodule Library.Authors.Listing.Authors do
  @moduledoc "Queries over authors."

  # `types:` tells the proxy generator the id is a UUID; the struct default is only a string.
  use Arc.ReadModel, model: Library.Authors.Author, types: [id: :uuid]

  alias Library.Authors.Author

  @doc "All authors."
  @query many: true
  def all_authors(_args, ctx), do: Chronicle.all(Author, ctx.chronicle)

  @doc "One author by id."
  @query params: [id: :uuid], many: false
  def author_by_id(%{id: id}, ctx), do: Chronicle.read_model(Author, id, ctx.chronicle)

  @doc "All authors, kept current: re-runs whenever Chronicle changes an author."
  @observe many: true, watch: [Author]
  def live_authors(_args, ctx), do: Chronicle.all(Author, ctx.chronicle)
end
```

Pass `ctx.chronicle` to Chronicle calls so the query uses the client Arc was configured with.

## Options

| Option | Effect |
| --- | --- |
| `params: [name: type]` | Typed arguments. `name: {type, optional: true}` makes one optional |
| `many: bool` | The query returns a list (default `true`) |
| `authorize:` / `allow_anonymous: true` | Override the module-level `authorize` |
| `http_method: :get \| :query` | Prefer one method in the generated client |
| `watch: [Model]` | (`@observe`) re-run when Chronicle changes these read models |
| `topics: [term]` | (`@observe`) re-run when `Arc.Notifier.notify/2` is called with the topic |

`@doc` becomes the query's summary. `use Arc.ReadModel, types: [id: :uuid]` overrides inferred field types for the generated TypeScript: Arc infers a type from each struct default, and `""` or `nil` reads as a string.

Arguments arrive converted: `%{id: "…"}` has been cast to the declared type, and a missing required argument or a value of the wrong type is rejected as `malformedRequest` before your function runs.

## Paging and sorting

A list returned by a query is sorted and paged in memory by Arc when the client asks, using `page` and `pageSize` (zero-based) and `sortBy` and `sortDirection`. The result envelope reports `paging` with `totalItems` and `totalPages`.

```shell
curl 'localhost:4000/api/authors/listing/all-authors?page=0&pageSize=10&sortBy=name&sortDirection=desc'
```

Those four parameters are reserved and matched case-insensitively; every other query-string parameter is an argument. `QUERY` requests carry the same in a JSON body:

```json
{ "arguments": {}, "paging": { "page": 0, "pageSize": 10 }, "sorting": { "field": "name", "direction": "desc" } }
```

For a large collection, page in the database instead and return an `Arc.Page`. Arc then reports its paging and does not touch the items.

```elixir
{:ok, %Arc.Page{items: items, total: total, page: page, size: size}}
```

## Observable queries

An `@observe` query is the same function, run again whenever its inputs change, with every result pushed to the client. A client can read it three ways from the same route:

- A plain `GET` returns the current result.
- `Accept: text/event-stream` opens Server-Sent Events, one `data:` message per result.
- A WebSocket upgrade, or the shared hub at `/.cratis/queries/ws`, which carries many subscriptions on one connection.
- The shared Server-Sent Events hub at `/.cratis/queries/sse`: the same protocol and the same many subscriptions on one stream, for clients that cannot or do not want a WebSocket. See [Hubs](#hubs).

The generated React client chooses the WebSocket hub by default; `queryTransportMethod` selects the SSE one.

On the client the choice is two values, `QueryTransportMethod` and `ObservableQueryTransferMode`, which the showcase's toolbar sets:

```tsx
// From: Samples/showcase/frontend/src/main.tsx
const [transport, setTransport] = useState<QueryTransportMethod>(QueryTransportMethod.WebSocket);
```

```tsx
// From: Samples/showcase/frontend/src/main.tsx
const [transferMode, setTransferMode] = useState<ObservableQueryTransferMode>(ObservableQueryTransferMode.Delta);
```

Each subscription is a process under your Arc application, started when the client subscribes and ended when its connection ends. It is `restart: :temporary`, so a failing subscription ends instead of looping; the client resubscribes. This needs `MyApp.Arc` in your supervision tree.

### Hubs

Both hubs speak the same protocol (`Connected`, `Subscribe`, `Unsubscribe`, `QueryResult`, `Unauthorized`, `Error`, `Ping`/`Pong`), with revisions so that a delayed subscribe cannot bring back a subscription that was cancelled. Each subscription goes through the ordinary query pipeline, so authorization, filters and the tenant apply as for a `GET`.

| | WebSocket | Server-Sent Events |
| --- | --- | --- |
| Open | `GET /.cratis/queries/ws` upgrade | `GET /.cratis/queries/sse` streams `data:` events; the first is `Connected` with the connection id |
| Subscribe | a `Subscribe` message | `POST /.cratis/queries/sse/subscribe` with `{connectionId, queryId, revision, request}` |
| Unsubscribe | an `Unsubscribe` message | `POST /.cratis/queries/sse/unsubscribe` with `{connectionId, queryId, revision}` |
| Needs | nothing special | an answer of `404` for an unknown connection or a different caller, `400` for a malformed body |

A browser `WebSocket` and `EventSource` cannot set request headers, so authenticate them with cookies, which an Arc authentication handler or a plug in front of Arc can read; the showcase sample shows one that turns cookies into the identity and tenant headers.

A subscription's `transferMode` shapes what it receives: `full` sends a snapshot every time, `delta` sends a snapshot first and afterwards only the change set (`added`, `replaced`, `removed`), and without a preference every emission carries both. The change set is computed on the hub, so a source needs nothing extra to support it.

### What triggers a re-run

`watch: [Author]` subscribes to Chronicle's change stream for that read model. For anything else, declare topics and notify them:

```elixir
@observe many: true, topics: ["authors"]
def live_authors(_args, _ctx), do: {:ok, MyApp.Authors.list()}

# somewhere that changes authors
Arc.Notifier.notify(MyApp.Arc, "authors")
```

`Arc.Notifier` reaches subscriptions on the same node. To reach every node, broadcast with `Phoenix.PubSub` and call `notify/2` in the receiver on each node.

Re-runs are debounced by 25 ms, so a burst of changes produces one result.

## Run a query from code

```elixir
result = Arc.query(MyApp.Arc, Library.Authors.Listing.Authors, :all_authors, %{}, page: 0, page_size: 10)
result.data
```

The result is an `Arc.QueryResult`; `Arc.QueryResult.to_wire/1` is the HTTP envelope, documented field by field in [Result envelopes](results.md).

## Next steps

- [LiveView](live-view.md) keeps an assign current from an observable query.
- [React and generated proxies](react-proxies.md) turns each query into a typed hook.
