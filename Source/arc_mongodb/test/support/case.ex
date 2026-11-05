# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule MongoFixtures.Case do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :mongodb
      import MongoFixtures.Case
    end
  end

  setup context do
    database = Arc.MongoDB.Test.unique_database("arc_test")
    url = System.get_env("MONGODB_URL", "mongodb://localhost:27017/?directConnection=true")

    mongodb =
      [server: url, database: database]
      |> Keyword.merge(Map.get(context, :mongo_options, []))

    previous = Application.get_env(:cratis_arc_mongodb, MongoFixtures.App)

    Application.put_env(:cratis_arc_mongodb, MongoFixtures.App,
      mongodb: mongodb,
      tenancy: Map.get(context, :tenancy, [])
    )

    Arc.Application.refresh(MongoFixtures.App)
    start_supervised!(MongoFixtures.App)
    start_supervised!({Arc.MongoDB, application: MongoFixtures.App})

    on_exit(fn ->
      cleanup(database, url)
      if previous, do: Application.put_env(:cratis_arc_mongodb, MongoFixtures.App, previous)
    end)

    %{database: database, url: url, ctx: Arc.context(MongoFixtures.App)}
  end

  def tenant(tenant), do: Arc.context(MongoFixtures.App, tenant: tenant)

  # The app is stopped by the time on_exit runs, so reach the databases through a connection of
  # our own.
  defp cleanup(database, url) do
    conn = Arc.MongoDB.Test.connect(url)

    {:ok, %{"databases" => databases}} =
      Mongo.issue_command(conn, [listDatabases: 1], :read, database: "admin")

    for %{"name" => name} <- databases, String.starts_with?(name, database) do
      Mongo.drop_database(conn, name)
    end

    GenServer.stop(conn)
  end
end
