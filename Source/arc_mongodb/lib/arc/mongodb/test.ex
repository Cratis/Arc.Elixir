# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.Test do
  @moduledoc """
  Helpers for testing code that uses `Arc.MongoDB` against a real MongoDB.

  Tests run against a server you start (a container is enough, `docker run -p 27017:27017 mongo`;
  observation needs it to be a replica set). Give every test run its own databases so tests do not
  see each other's data, and drop them afterwards:

      setup do
        database = Arc.MongoDB.Test.unique_database("library")
        Application.put_env(:my_app, MyApp.Arc, mongodb: [server: url, database: database])
        Arc.Application.refresh(MyApp.Arc)
        start_supervised!({Arc.MongoDB, application: MyApp.Arc})
        on_exit(fn -> Arc.MongoDB.Test.drop_databases(MyApp.Arc, database, ["acme"]) end)
      end
  """

  @doc "A database name that is unique to this test run, `\"<prefix>_<random>\"`."
  @spec unique_database(String.t()) :: String.t()
  def unique_database(prefix),
    do: prefix <> "_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

  @doc """
  Drops the default database and the databases of `tenants`, as resolved for the application.
  Does nothing when the MongoDB processes are not running.
  """
  @spec drop_databases(module(), String.t(), [String.t()]) :: :ok
  def drop_databases(app, _database, tenants \\ []) do
    if Process.whereis(Arc.MongoDB.Supervisor.name(app)) do
      for tenant <- [nil | tenants] do
        ctx = Arc.context(app, tenant: tenant)
        {:ok, connection} = Arc.MongoDB.Connections.connect(app, ctx.tenant)
        Mongo.drop_database(connection.topology, connection.database)
      end
    end

    :ok
  end

  @doc """
  Starts a driver connection to `url` that is ready to use, for checking what is stored.
  """
  @spec connect(String.t()) :: pid()
  def connect(url) do
    {:ok, conn} = Mongo.start_link(url: url, pool_size: 1, database: "admin")
    Arc.MongoDB.Connections.wait_until_ready(conn, System.monotonic_time(:millisecond) + 5_000)
    conn
  end

  @doc """
  Whether a MongoDB answers at `url`'s first host, for skipping tests when none is running.
  """
  @spec available?(String.t()) :: boolean()
  def available?(url) do
    with [_, host, port] <- Regex.run(~r{^mongodb://(?:[^@/]+@)?([^:/,?]+):?(\d+)?}, url) |> pad(),
         {:ok, socket} <-
           :gen_tcp.connect(to_charlist(host), String.to_integer(port), [], 500) do
      :gen_tcp.close(socket)
      true
    else
      _ -> false
    end
  end

  defp pad([whole, host]), do: [whole, host, "27017"]
  defp pad([_, _, ""] = list), do: List.replace_at(list, 2, "27017")
  defp pad(other), do: other
end
