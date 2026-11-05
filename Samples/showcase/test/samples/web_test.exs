# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.WebTest do
  use ExUnit.Case

  import Plug.Conn
  import Plug.Test

  defp call(conn), do: Samples.Router.call(conn, Samples.Router.init([]))

  defp principal(id, name, roles) do
    Base.encode64(
      Jason.encode!(%{
        identityProvider: "demo",
        userId: id,
        userDetails: name,
        userRoles: roles,
        claims: []
      })
    )
  end

  test "health" do
    assert %{status: 200, resp_body: "ok"} = call(conn(:get, "/health"))
  end

  test "the contract is served by the plain Plug router" do
    conn = call(conn(:get, "/api/query-showcase/by-id?id=4"))

    assert conn.status == 200
    assert %{"data" => %{"id" => 4, "name" => "Item #4"}} = Jason.decode!(conn.resp_body)
  end

  test "nobody is signed in without credentials" do
    assert %{status: 401} = call(conn(:get, "/.cratis/me"))
  end

  test "the sign-in cookie is the identity, as the hubs of a browser need it" do
    conn =
      conn(:get, "/.cratis/me")
      |> put_req_header("cookie", "x-ms-client-principal=#{principal("u1", "Ada", ["User"])}")
      |> call()

    assert conn.status == 200

    assert %{
             "id" => "u1",
             "name" => "Ada",
             "roles" => ["User"],
             "details" => %{"displayName" => "Hello, Ada", "tenant" => "Default"}
           } = Jason.decode!(conn.resp_body)
  end

  test "the tenant comes from the header or the cookie, and reaches the identity provider" do
    signed_in = "x-ms-client-principal=#{principal("u1", "Ada", [])}"

    from_cookie =
      conn(:get, "/.cratis/me")
      |> put_req_header("cookie", signed_in <> "; x-cratis-tenant-id=acme")
      |> call()

    assert %{"details" => %{"tenant" => "acme"}} = Jason.decode!(from_cookie.resp_body)

    from_header =
      conn(:get, "/.cratis/me")
      |> put_req_header("cookie", signed_in <> "; x-cratis-tenant-id=acme")
      |> put_req_header("x-cratis-tenant-id", "globex")
      |> call()

    assert %{"details" => %{"tenant" => "globex"}} = Jason.decode!(from_header.resp_body)
  end

  test "a request for a secured artifact is forbidden without the role" do
    conn =
      conn(:get, "/api/cross-cutting-authorization/secured")
      |> put_req_header("cookie", "x-ms-client-principal=#{principal("u1", "Ada", ["User"])}")
      |> call()

    assert conn.status == 403
  end

  test "the discovery routes list the commands and queries" do
    conn = call(conn(:get, "/.cratis/queries"))

    names = conn.resp_body |> Jason.decode!() |> Enum.map(& &1["name"])
    assert "Observe" in names
    assert "WatchAll" in names
  end

  test "the SSE hub's control routes are served: an unknown connection is a 404" do
    conn =
      conn(
        :post,
        "/.cratis/queries/sse/subscribe",
        Jason.encode!(%{connectionId: "x", queryId: "q", request: %{}})
      )
      |> put_req_header("content-type", "application/json")
      |> call()

    assert conn.status == 404
  end
end
