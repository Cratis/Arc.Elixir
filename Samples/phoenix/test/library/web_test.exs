# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.WebTest do
  use Arc.Test.Case,
    application: Library.Arc,
    configure: true,
    event_types: [Library.Authors.AuthorRegistered, Library.Authors.AuthorRenamed]

  import Plug.Conn
  import Plug.Test

  alias Library.Authors.AuthorRegistered

  defp call(conn), do: Library.Web.Endpoint.call(conn, Library.Web.Endpoint.init([]))

  test "the endpoint serves the Arc HTTP contract for commands", %{arc: arc} do
    id = Arc.new_id()

    conn =
      conn(
        :post,
        "/api/authors/registration/register-author",
        Jason.encode!(%{id: id, name: "Ada Lovelace"})
      )
      |> put_req_header("content-type", "application/json")
      |> call()

    assert conn.status == 200
    assert %{"isSuccess" => true} = Jason.decode!(conn.resp_body)
    Arc.Test.assert_appended(arc, AuthorRegistered, event_source_id: id)
  end

  test "a validation failure is a 400 envelope naming the member" do
    conn =
      conn(
        :post,
        "/api/authors/registration/register-author",
        Jason.encode!(%{id: Arc.new_id(), name: "A"})
      )
      |> put_req_header("content-type", "application/json")
      |> call()

    assert conn.status == 400
    assert %{"validationResults" => [%{"members" => ["name"]}]} = Jason.decode!(conn.resp_body)
  end

  test "the demo sign-in decides who may rename" do
    rename = Jason.encode!(%{id: Arc.new_id(), name: "Ada King"})

    denied =
      conn(:post, "/api/authors/registration/rename-author", rename)
      |> put_req_header("content-type", "application/json")
      |> call()

    allowed =
      conn(:post, "/api/authors/registration/rename-author", rename)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-demo-user", "ed")
      |> put_req_header("x-demo-roles", "editor")
      |> call()

    assert denied.status == 403
    assert allowed.status == 200
  end

  test "the command catalog lists the commands with their routes" do
    conn = conn(:get, "/.cratis/commands") |> call()

    assert conn.status == 200
    routes = conn.resp_body |> Jason.decode!() |> Enum.map(& &1["route"])
    assert "/api/authors/registration/register-author" in routes
  end

  test "ordinary Phoenix routes still work beside Arc" do
    conn = conn(:get, "/health") |> call()

    assert conn.status == 200
    assert %{"status" => "ok"} = Jason.decode!(conn.resp_body)
  end

  test "the identity endpoint serves the signed-in user with typed details" do
    anonymous = conn(:get, "/.cratis/me") |> call()

    editor =
      conn(:get, "/.cratis/me")
      |> put_req_header("x-demo-user", "ed")
      |> put_req_header("x-demo-roles", "editor")
      |> call()

    assert anonymous.status == 401

    assert %{
             "name" => "ed",
             "roles" => ["editor"],
             "isAuthenticated" => true,
             "details" => %{"displayName" => "Hello, ed", "canRename" => true}
           } = Jason.decode!(editor.resp_body)
  end

  test "development tools can list the users to sign in as" do
    conn = conn(:get, "/.cratis/users") |> call()

    users = Jason.decode!(conn.resp_body)
    assert Enum.map(users, & &1["microsoftIdentity"]["userId"]) == ["ada", "ed"]
  end
end
