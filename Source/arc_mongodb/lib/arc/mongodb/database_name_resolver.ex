# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.DatabaseNameResolver do
  @moduledoc """
  Names the database of a tenant.

  The default resolver returns the configured database for the default tenant (`nil`, empty or
  `"Default"`, see `Arc.Tenancy.default?/1`) and `"<database>+<tenant>"` for a named one, which
  lines up with the database Chronicle projects read models into when the event store is named
  like the database.

  A different convention is a module:

      defmodule MyApp.TenantDatabases do
        @behaviour Arc.MongoDB.DatabaseNameResolver

        @impl true
        def resolve(nil, options), do: options.database
        def resolve(tenant, options), do: tenant <> "_" <> options.database
      end

      config :my_app, MyApp.Arc, mongodb: [database_resolver: MyApp.TenantDatabases, ...]

  A resolver only changes the database name. To change the server or the credentials per tenant,
  use `Arc.MongoDB.ConnectionResolver`. Database naming is not authorization: resolve the tenant
  safely and check that the caller belongs to it. Change the naming of a database in use only as a
  data migration.
  """

  @doc "The name of the database for `tenant` (`nil` when no tenant is set)."
  @callback resolve(tenant :: String.t() | nil, options :: Arc.MongoDB.Options.t()) :: String.t()
end

defmodule Arc.MongoDB.DatabaseNameResolver.Default do
  @moduledoc false
  @behaviour Arc.MongoDB.DatabaseNameResolver

  @impl true
  def resolve(tenant, options) do
    if Arc.Tenancy.default?(tenant), do: options.database, else: "#{options.database}+#{tenant}"
  end
end
