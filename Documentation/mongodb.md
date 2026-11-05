---
title: MongoDB
description: Store documents in MongoDB with tenant-aware databases, naming conventions, connection resolution and observable queries over change streams.
---

`cratis_arc_mongodb` gives an Arc application document storage with the conventions the rest of Arc expects, as the MongoDB package does on .NET. It does not need Chronicle.

```elixir
{:cratis_arc_mongodb, "~> 0.0"}
```

Describe the connection on the application, in the showcase sample's `config/runtime.exs`:

```elixir
# From: Samples/showcase/config/runtime.exs
  mongodb: [
    server: System.get_env("MONGODB_URL", "mongodb://localhost:27017/?replicaSet=rs0"),
    database: "samples",
    naming_policy: :camel_case
  ]
```

and start the package after the Arc application:

```elixir
# From: Samples/showcase/lib/samples/application.ex
      [Samples.Store, Samples.Arc, {Arc.MongoDB, application: Samples.Arc}] ++
```

Change streams, which [observation](#observe-a-collection) needs, require a replica set or a sharded cluster. A single node started with `--replSet` is enough; the showcase sample's `docker-compose.yml` starts one.

## Options

| Option | Default | |
| --- | --- | --- |
| `server` | none, required | The connection string. Keep credentials out of source control |
| `database` | none, required | The database of the default tenant |
| `naming_policy` | `:none` | `:none`, `:camel_case`, `:snake_case` or a module implementing `Arc.MongoDB.NamingPolicy` |
| `direct_connection` | the connection string decides | Connect to the one server given instead of discovering the replica set |
| `database_resolver` | the default naming | A module implementing `Arc.MongoDB.DatabaseNameResolver` |
| `server_resolver` | the configured `server` | A module implementing `Arc.MongoDB.ServerResolver` |
| `connection_resolution` | none | Where to connect, and as whom, per tenant: [see below](#place-tenants-on-their-own-servers) |
| `pool_size` | `5` | Connections per server and identity |

## Documents

A document is a struct. `use Arc.MongoDB.Document` says more than the struct's defaults can.

```elixir
# From: Samples/showcase/lib/samples/mongo_watcher/watcher_item.ex
  use Arc.MongoDB.Document, types: [id: :uuid, created_at: :datetime]

  defstruct id: "", name: "", created_at: ~U[1970-01-01 00:00:00Z]
```

Without `types:`, a field is stored as its value is: `types:` is for what the struct's defaults cannot say, such as a UUID or a date.

| Type | Stored as |
| --- | --- |
| `:string`, `:integer`, `:float`, `:boolean` | the same |
| `:uuid` | binary, subtype 4 (the standard UUID representation) |
| `:object_id` | `ObjectId`, a 24 character hexadecimal string in the struct |
| `:datetime` | a UTC date time, to the millisecond |
| `:date` | a UTC date time at noon of the day |
| `{:list, type}` | an array, never `nil` when read |
| `:map` | an embedded document |
| a `Chronicle.Concept` | the primitive it wraps |
| a struct module | an embedded document |

The `id` field is stored as `_id`. The naming policy names members and collections: with `:camel_case`, `display_name` is `displayName` and `Library.Books.Book` is the collection `book`; a document can name its own collection with `collection:`. Members the struct does not know are ignored when reading, and members missing from a document take the struct's defaults.

## Use a collection

Every function takes `{ctx, document_module}`: the collection is resolved from the context, so the tenant of the request picks the database.

```elixir
# Illustrative; `Book` is any `Arc.MongoDB.Document`
Arc.MongoDB.insert({ctx, Book}, %Book{id: Arc.new_id(), title: "Dune"})
Arc.MongoDB.find({ctx, Book}, %{title: "Dune"}, sort: [published: :desc], limit: 10)
Arc.MongoDB.find_by_id({ctx, Book}, id)
Arc.MongoDB.update({ctx, Book}, id, %{"$set" => %{title: "Dune Messiah"}, "$inc" => %{copies: 1}})
Arc.MongoDB.save({ctx, Book}, book)       # replace, or create
Arc.MongoDB.delete({ctx, Book}, id)
Arc.MongoDB.count({ctx, Book}, %{copies: %{"$gt" => 0}})
```

In a filter, atom keys are fields of the struct, translated to their stored names and values (a UUID field takes a UUID string), while string keys are raw MongoDB (`"$or"`, `"$text"`, dotted paths). A field the struct does not have raises instead of matching nothing. An insert or save that breaks a unique index (`Arc.MongoDB.create_index/3`) returns `{:error, :duplicate}`.

`Arc.MongoDB.provide/4` loads a document for a command's `provide/2`, and `Arc.MongoDB.page/3` returns an `Arc.Page` paged and sorted in the database from what the client asked for:

```elixir
# From: Samples/showcase/lib/samples/mongo_watcher/items/queries.ex
  @query many: true
  def paged(_args, ctx), do: {:ok, Arc.MongoDB.page({ctx, WatcherItem}, %{})}
```

## Tenancy

The tenant of the request (see [Tenancy](tenancy.md)) is a database. The default tenant uses `database`; a named tenant `acme` uses `database+acme`, which lines up with the database Chronicle projects read models into when the event store is named like the database. Another convention is a `database_resolver`:

```elixir
defmodule MyApp.TenantDatabases do
  @behaviour Arc.MongoDB.DatabaseNameResolver

  @impl true
  def resolve(nil, options), do: options.database
  def resolve(tenant, options), do: tenant <> "_" <> options.database
end
```

Naming a database is not authorizing the caller to use it. Changing the naming of a database in use is a data migration.

## Place tenants on their own servers

`connection_resolution` tells Arc where to connect and as whom, per tenant, using the [connection resolution contract](https://github.com/Cratis/Arc/blob/main/Documentation/connection-resolution-contract.md) shared with the other Arc implementations. There are two slots, `connection` (the connection string and database) and `identity` (user name and password), and each takes `:default`, a rule, an endpoint or a module:

```elixir
connection_resolution: [
  connection: {:template, database: "tenant-{tenant}"},
  identity: {:http, endpoint: "https://platform.example/connections",
                    headers: [{"x-api-key", System.fetch_env!("PLATFORM_KEY")}]},
  cache_duration: 300
]
```

A module implements `Arc.MongoDB.ConnectionResolver` and answers `{:ok, %Arc.MongoDB.ResolvedConnection{}}`. Answers are cached in memory by purpose and tenant, never by credential, until one minute before their expiry; a connection that fails to authenticate drops its cached answer so the next attempt picks up rotated credentials. Clients are shared per server and identity. A resolved `database` replaces the `database+tenant` naming entirely, including for the default tenant, which resolves as `Default`. An OIDC `accessToken` is refused: the Elixir MongoDB driver has no such mechanism.

## Observe a collection

```elixir
# From: Samples/showcase/lib/samples/mongo_watcher/notes/queries.ex
  @observe many: true,
           watch: [Arc.MongoDB.watch(WatcherNote), Arc.MongoDB.watch(WatcherItem)]
  def watch_all(_args, ctx),
    do: {:ok, Arc.MongoDB.all({ctx, WatcherNote}, sort: [created_at: :asc])}
```

This query watches both the notes and the items, so it re-runs when either changes. Watch only the notes, as `observe_all` in the same module does, to re-run on notes alone.

The query re-runs when the collection changes, with the tenant of each subscription, and the result is pushed over either hub. One database-level change stream is shared by every observer of a database, however many queries watch it; it reopens from its resume token after a failure, tells the observers to run again, and closes when the last observer is gone. A query can watch several collections, and a watch on a collection another query writes to is what lets one change update several lists. Observation says that a collection changed; the query decides what to send.

`Arc.Watch` is the behaviour behind this: any module can be a source of changes for `watch:`.

## Test

```elixir
setup do
  database = Arc.MongoDB.Test.unique_database("library")
  # configure `mongodb: [server: url, database: database]`, then
  start_supervised!({Arc.MongoDB, application: MyApp.Arc})
  on_exit(fn -> Arc.MongoDB.Test.drop_databases(MyApp.Arc, database, ["acme"]) end)
end
```

The package's own tests run against a real MongoDB (`MONGODB_URL`, default `mongodb://localhost:27017/?directConnection=true`) and are skipped when none answers.
