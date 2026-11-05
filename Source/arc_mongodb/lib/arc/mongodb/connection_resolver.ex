# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.ConnectionResolver do
  @moduledoc """
  Tells Arc where to connect and who to connect as, for each tenant.

  With one configured connection string, Arc cannot follow a platform that places each tenant's
  database somewhere of its own. A resolver is asked when a connection is needed, with a
  *request* describing what is being connected, and answers with the parts it knows as a
  `Arc.MongoDB.ResolvedConnection`; the rest stays as configured.

  There are two slots, and each takes a resolver:

    * `:connection` - where to connect: the connection string and the database
    * `:identity` - who to connect as: a user name and password

  The `:connection` answer is applied first and the `:identity` answer on top of it. A resolver is

    * `:default` - nothing to resolve (the default of both slots)
    * `{:template, connection_string: "...", database: "tenant-{tenant}"}` -
      `Arc.MongoDB.ConnectionResolver.Template`, for placement that follows a naming rule
    * `{:http, endpoint: "https://...", headers: [...], timeout: 10_000}` -
      `Arc.MongoDB.ConnectionResolver.Http`, which calls your platform over the
      [connection resolution contract](https://www.cratis.io/arc/connection-resolution-contract/)
    * a module implementing this behaviour

          defmodule MyApp.TenantConnections do
            @behaviour Arc.MongoDB.ConnectionResolver

            @impl true
            def resolve(%{scope: %{"tenant" => tenant}}) do
              {:ok, %Arc.MongoDB.ResolvedConnection{database: "app_" <> tenant}}
            end
          end

      configured as

          config :my_app, MyApp.Arc,
            mongodb: [
              server: "mongodb://cluster.example",
              database: "app",
              connection_resolution: [connection: MyApp.TenantConnections]
            ]

  ## The request

  `%{storage: "MongoDB", purpose: :runtime | :schema, scope: %{"tenant" => tenant}}`. The tenant
  is `"Default"` when none is set. `purpose` is `:runtime` unless the code says otherwise with the
  `purpose:` option of `Arc.MongoDB.collection/3`; use `:schema` to be handed a more privileged
  identity for schema changes such as creating indexes.

  ## Caching and credentials

  Answers are cached **in memory only**, by purpose and tenant, never by credential. An answer
  lives until one minute before its `:expires_at`, or for the `:cache_duration` (five minutes) when
  the resolver gave none. A connection that fails to authenticate drops its cached answer, so the
  next attempt resolves again and picks up rotated credentials. Clients are shared per server and
  identity, never across identities.

  A resolved `:database` replaces the `<database>+<tenant>` naming entirely, including for the
  default tenant. Data stored under the old names stays there: switching is a data migration.
  """

  @type request :: %{
          storage: String.t(),
          purpose: :runtime | :schema,
          scope: %{optional(String.t()) => String.t()}
        }

  @callback resolve(request()) ::
              {:ok, Arc.MongoDB.ResolvedConnection.t()} | :unchanged | {:error, term()}
end
