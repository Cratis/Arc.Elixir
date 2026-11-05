# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.ConnectionResolutionTest do
  use MongoFixtures.Case

  alias Arc.MongoDB.{ConnectionResolver, Connections, Options, ResolvedConnection}
  alias MongoFixtures.Books.Book

  @request %{storage: "MongoDB", purpose: :runtime, scope: %{"tenant" => "acme"}}

  describe "the template resolver" do
    test "fills placeholders from the scope, purpose and storage" do
      assert {:ok, %ResolvedConnection{database: "tenant-acme-Runtime-MongoDB"}} =
               ConnectionResolver.Template.resolve(@request,
                 database: "tenant-{tenant}-{purpose}-{storage}"
               )
    end

    test "a placeholder without a value fails instead of connecting somewhere unintended" do
      assert {:error, message} =
               ConnectionResolver.Template.resolve(@request, database: "{region}-{tenant}")

      assert message =~ "{region}"
    end

    @tag mongo_options: [
           connection_resolution: [connection: {:template, database: "tenant-{tenant}"}]
         ]
    test "places each tenant's database, including the default tenant", %{ctx: ctx} do
      assert Arc.MongoDB.locate({tenant("acme"), Book}) == {"tenant-acme", "books"}
      assert Arc.MongoDB.locate({ctx, Book}) == {"tenant-Default", "books"}

      Arc.MongoDB.insert({tenant("acme"), Book}, %Book{id: "11111111-1111-4111-8111-111111111111"})

      assert Arc.MongoDB.count({tenant("acme"), Book}) == 1
      assert Arc.MongoDB.count({ctx, Book}) == 0

      {:ok, conn} = Connections.connect(MongoFixtures.App, "acme")
      Mongo.drop_database(conn.topology, "tenant-acme")
      Mongo.drop_database(conn.topology, "tenant-Default")
    end
  end

  describe "the http resolver" do
    defmodule Platform do
      use Plug.Builder

      plug(:answer)

      def answer(conn, _opts) do
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          :platform_test,
          {:asked, Jason.decode!(body), Plug.Conn.get_req_header(conn, "x-api-key")}
        )

        case Agent.get(:platform_answer, & &1) do
          {:json, status, json} ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(status, json)

          {:status, status} ->
            Plug.Conn.send_resp(conn, status, "")
        end
      end
    end

    setup do
      Process.register(self(), :platform_test)
      {:ok, _} = Agent.start_link(fn -> {:status, 204} end, name: :platform_answer)
      {:ok, server} = Bandit.start_link(plug: Platform, port: 0, ip: :loopback)
      {:ok, {_, port}} = ThousandIsland.listener_info(server)
      %{endpoint: "http://localhost:#{port}/connections", port: port}
    end

    defp answer(value), do: Agent.update(:platform_answer, fn _ -> value end)

    test "posts the contract request and reads the answer", %{endpoint: endpoint} do
      answer(
        {:json, 200,
         ~s({"ConnectionString": "mongodb://other:27017", "Database": "placed", "Identity": {"userName": "u", "password": "p"}, "expiresAt": "2099-01-01T00:00:00+00:00"})}
      )

      assert {:ok, resolved} =
               ConnectionResolver.Http.resolve(@request,
                 endpoint: endpoint,
                 headers: [{"x-api-key", "secret"}]
               )

      assert_received {:asked,
                       %{
                         "storage" => "MongoDB",
                         "purpose" => "Runtime",
                         "scope" => %{"tenant" => "acme"}
                       }, ["secret"]}

      assert resolved.connection_string == "mongodb://other:27017"
      assert resolved.database == "placed"
      assert resolved.identity == %{user_name: "u", password: "p", access_token: nil}
      assert resolved.expires_at == ~U[2099-01-01 00:00:00Z]
    end

    test "204 keeps the configuration, an error status fails", %{endpoint: endpoint} do
      answer({:status, 204})
      assert :unchanged = ConnectionResolver.Http.resolve(@request, endpoint: endpoint)

      answer({:status, 500})
      assert {:error, message} = ConnectionResolver.Http.resolve(@request, endpoint: endpoint)
      assert message =~ "500"

      answer({:json, 200, "[]"})
      assert {:error, _} = ConnectionResolver.Http.resolve(@request, endpoint: endpoint)
    end

    test "resolutions are cached by tenant, and invalidated when asked", %{endpoint: endpoint} do
      answer({:json, 200, ~s({"database": "placed"})})

      start_resolution(endpoint)
      assert Arc.MongoDB.locate({tenant("acme"), Book}) == {"placed", "books"}
      assert_received {:asked, _, _}
      assert Arc.MongoDB.locate({tenant("acme"), Book}) == {"placed", "books"}
      refute_received {:asked, _, _}

      # Another tenant is another request.
      Arc.MongoDB.locate({tenant("globex"), Book})
      assert_received {:asked, %{"scope" => %{"tenant" => "globex"}}, _}

      answer({:json, 200, ~s({"database": "moved"})})
      Connections.invalidate(MongoFixtures.App, "acme")
      assert Arc.MongoDB.locate({tenant("acme"), Book}) == {"moved", "books"}
    end

    test "an answer's expiry ends its caching", %{endpoint: endpoint} do
      soon = DateTime.utc_now() |> DateTime.add(30) |> DateTime.to_iso8601()
      answer({:json, 200, ~s({"database": "short", "expiresAt": "#{soon}"})})

      start_resolution(endpoint)
      Arc.MongoDB.locate({tenant("acme"), Book})
      assert_received {:asked, _, _}

      # One minute before expiry the answer is already stale: it is asked for again.
      Arc.MongoDB.locate({tenant("acme"), Book})
      assert_received {:asked, _, _}
    end

    test "a failing resolver fails the connection with its reason", %{endpoint: endpoint} do
      answer({:status, 503})
      start_resolution(endpoint)

      assert_raise RuntimeError, ~r/503/, fn -> Arc.MongoDB.collection(tenant("acme"), Book) end
    end

    test "an access token is refused: the driver has no OIDC", %{endpoint: endpoint} do
      answer({:json, 200, ~s({"identity": {"accessToken": "eyJ"}})})
      start_resolution(endpoint)

      assert_raise RuntimeError, ~r/OIDC/, fn -> Arc.MongoDB.collection(tenant("acme"), Book) end
    end

    defp start_resolution(endpoint) do
      raw = Application.get_env(:cratis_arc_mongodb, MongoFixtures.App)[:mongodb]

      mongodb =
        Keyword.put(raw, :connection_resolution,
          identity: {:http, endpoint: endpoint},
          cache_duration: 300
        )

      Application.put_env(:cratis_arc_mongodb, MongoFixtures.App, mongodb: mongodb)
      Arc.Application.refresh(MongoFixtures.App)
    end
  end

  describe "the identity of a connection" do
    test "a user name and password authenticate against the connection string's database or admin" do
      options = Options.build(server: "mongodb://localhost", database: "app")
      identity = %{user_name: "ada", password: "secret"}

      with_db = %ResolvedConnection{
        connection_string: "mongodb://host/library",
        identity: identity
      }

      plain = %ResolvedConnection{connection_string: "mongodb://host", identity: identity}

      with_source =
        %ResolvedConnection{
          connection_string: "mongodb://host/library?authSource=users",
          identity: identity
        }

      assert Connections.driver_options(options, with_db)[:auth_source] == "library"
      assert Connections.driver_options(options, plain)[:auth_source] == "admin"
      assert Connections.driver_options(options, with_source)[:auth_source] == "users"
      assert Connections.driver_options(options, plain)[:username] == "ada"
    end

    test "no identity leaves the connection string's own credentials alone" do
      options = Options.build(server: "mongodb://localhost", database: "app")
      resolved = %ResolvedConnection{connection_string: "mongodb://u:p@host/db"}
      driver = Connections.driver_options(options, resolved)

      assert driver[:username] == "u"
      # The driver keeps the password from the connection string out of its options.
      assert driver[:password] != nil
    end

    test "direct_connection makes the topology single" do
      options =
        Options.build(server: "mongodb://localhost", database: "app", direct_connection: true)

      resolved = %ResolvedConnection{connection_string: "mongodb://host"}
      assert Connections.driver_options(options, resolved)[:type] == :single
    end
  end
end
