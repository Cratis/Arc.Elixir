# Arc for Elixir: MongoDB

`cratis_arc_mongodb` is the MongoDB package of [Arc for Elixir](../../README.md): document storage with the conventions the rest of Arc expects.

- **Tenancy.** The tenant of a request selects the database: the configured one for the default tenant and `<database>+<tenant>` for a named one, or your own naming.
- **Conventions.** Structs are the documents. Naming policies, `_id`, standard UUIDs, dates, concepts and nested documents are handled in one place.
- **Connection resolution.** Place tenants on servers and credentials of their own, by rule, by an endpoint that follows the shared connection resolution contract, or by a module.
- **Observation.** `@observe watch: [Arc.MongoDB.watch(Book)]` re-runs a query when a collection changes, over one shared change stream per database.

```elixir
{:cratis_arc_mongodb, "~> 0.0"}
```

Read the [MongoDB guide](../../Documentation/mongodb.md) and run the [showcase sample](../../Samples/showcase).

## Develop

```shell
docker run -d --name mongo -p 127.0.0.1:27017:27017 mongo:7 --replSet rs0 --bind_ip_all
docker exec mongo mongosh --eval 'rs.initiate({_id:"rs0",members:[{_id:0,host:"localhost:27017"}]})'

mix deps.get
MONGODB_URL="mongodb://localhost:27017/?directConnection=true" mix test
```

Tests that need a MongoDB are skipped when none answers.
