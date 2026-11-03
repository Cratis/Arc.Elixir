# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Serves the test fixtures over HTTP for the runtime contract. Run from Source/arc with MIX_ENV=test.
# Prints `ARC_READY <port>` when it is listening.

defmodule ContractServer do
  use Plug.Builder
  import Plug.Conn

  plug Arc.Plug, application: ArcFixtures.App
  plug :test_routes

  # Adds an author and notifies the observable queries, so the runtime contract can watch a push.
  def test_routes(%{request_path: "/test/add-author"} = conn, _opts) do
    %{"name" => name} = Plug.Conn.Query.decode(conn.query_string)
    id = Arc.Context.new_correlation_id()
    ArcFixtures.Store.put(ArcFixtures.Store.all() ++ [%ArcFixtures.Authors.Author{id: id, name: name}])
    Arc.Notifier.notify(ArcFixtures.App, "authors")
    conn |> send_resp(200, id) |> halt()
  end

  def test_routes(conn, _opts), do: conn |> send_resp(404, "not found") |> halt()
end

{:ok, client} =
  Chronicle.Testing.start_supervised_client(event_types: [ArcFixtures.Authors.AuthorRegistered])

# The unsigned x-ms-client-principal headers are trusted here because this server is only reachable
# by the contract test; a real application enables that only behind an authenticating ingress.
Application.put_env(:cratis_arc, ArcFixtures.App,
  chronicle: [client: client],
  introspection: :anonymous,
  authentication: [Arc.Authentication.ClientPrincipal],
  trust_forwarded_identity_headers: true
)
Arc.Application.refresh(ArcFixtures.App)

{:ok, _} = Supervisor.start_link([ArcFixtures.App], strategy: :one_for_one)

ArcFixtures.Store.put([
  %ArcFixtures.Authors.Author{id: "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e", name: "Ada"},
  %ArcFixtures.Authors.Author{id: "8a1b2c3d-0f4e-4d0f-8f4e-0f4e4d0f8f4e", name: "Bob"},
  %ArcFixtures.Authors.Author{id: "9b2c3d4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e", name: "Cy"}
])

port = String.to_integer(System.get_env("PORT", "4747"))
{:ok, _} = Bandit.start_link(plug: ContractServer, port: port, ip: :loopback)
IO.puts("ARC_READY #{port}")
Process.sleep(:infinity)
