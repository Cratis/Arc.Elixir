# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.PlugTest do
  use Arc.Test.Case,
    application: ArcFixtures.App,
    configure: true,
    event_types: [ArcFixtures.Authors.AuthorRegistered]

  import Plug.Test
  import Plug.Conn

  alias ArcFixtures.Authors.AuthorRegistered

  @id "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"
  @register "/api/authors/registration/register-author"

  setup do
    ArcFixtures.Store.put([
      %ArcFixtures.Authors.Author{id: @id, name: "Ada"},
      %ArcFixtures.Authors.Author{id: "b", name: "Bob"}
    ])

    :ok
  end

  defp call(conn), do: Arc.Plug.call(conn, Arc.Plug.init(application: ArcFixtures.App))

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body)) |> put_req_header("content-type", "application/json")
  end

  defp decoded(conn), do: Jason.decode!(conn.resp_body)

  describe "commands" do
    test "POST executes the command and appends its event", %{arc: arc} do
      conn = post_json(@register, %{"id" => @id, "name" => "Ada"}) |> call()

      assert conn.status == 200
      assert %{"isSuccess" => true, "isValid" => true, "correlationId" => id} = decoded(conn)
      assert [^id] = get_resp_header(conn, "x-correlation-id")
      Arc.Test.assert_appended(arc, AuthorRegistered, event_source_id: @id)
    end

    test "reuses a valid correlation id and replaces an invalid one" do
      good = "22222222-2222-4222-8222-222222222222"

      conn =
        post_json(@register, %{"id" => @id, "name" => "Ada"})
        |> put_req_header("x-correlation-id", good)
        |> call()

      assert get_resp_header(conn, "x-correlation-id") == [good]

      conn =
        post_json(@register, %{"id" => @id, "name" => "Ada"})
        |> put_req_header("x-correlation-id", "<script>")
        |> call()

      assert [value] = get_resp_header(conn, "x-correlation-id")
      assert value =~ ~r/\A[0-9a-f-]{36}\z/
    end

    test "a validation failure answers 400 with the member", %{arc: arc} do
      conn = post_json(@register, %{"id" => @id, "name" => ""}) |> call()

      assert conn.status == 400

      assert %{"isValid" => false, "validationResults" => [%{"members" => ["name"]}]} =
               decoded(conn)

      Arc.Test.refute_appended(arc, AuthorRegistered)
    end

    test "/validate runs validation without appending", %{arc: arc} do
      conn = post_json(@register <> "/validate", %{"id" => @id, "name" => "Ada"}) |> call()

      assert conn.status == 200
      Arc.Test.refute_appended(arc, AuthorRegistered)
    end

    test "a malformed body is a 400 malformedRequest" do
      conn =
        conn(:post, @register, "{not json")
        |> put_req_header("content-type", "application/json")
        |> call()

      assert conn.status == 400
      assert %{"validationResults" => [%{"reason" => "malformedRequest"}]} = decoded(conn)
    end

    test "unknown fields are ignored" do
      conn = post_json(@register, %{"id" => @id, "name" => "Ada", "unexpected" => "x"}) |> call()
      assert conn.status == 200
    end

    test "authorization failure answers 403" do
      conn =
        post_json("/api/authors/registration/rename-author", %{"id" => @id, "name" => "Ada"})
        |> call()

      assert conn.status == 403
      assert %{"isAuthorized" => false} = decoded(conn)
    end

    test "a caller assigned a principal in the role is admitted" do
      conn =
        post_json("/api/authors/registration/rename-author", %{"id" => @id, "name" => "Ada"})
        |> assign(:arc_principal, Arc.Test.principal("root", ["admin"]))
        |> call()

      assert conn.status == 200
      assert %{"response" => "previous-" <> _} = decoded(conn)
    end

    test "X-Allowed-Severity is capped at Warning" do
      # 'forbidden' yields an Error (3) result; even a header of 3 only tolerates up to Warning (2).
      conn =
        post_json(@register, %{"id" => @id, "name" => "forbidden"})
        |> put_req_header("x-allowed-severity", "3")
        |> call()

      assert conn.status == 400
    end

    test "a non-Arc route passes through untouched" do
      conn = conn(:get, "/somewhere-else") |> call()
      refute conn.halted
      assert conn.status == nil
    end
  end

  describe "route admission" do
    test "wrong methods and unknown validation routes pass through" do
      for {method, path} <- [
            {:get, @register},
            {:get, @register <> "/validate"},
            {:post, "/api/missing/validate"},
            {:post, "/api/authors/listing/all-authors"},
            {:delete, "/api/authors/listing/all-authors"}
          ] do
        request = conn(method, path)
        assert call(request) == request
      end
    end
  end

  describe "queries" do
    test "GET returns the data envelope" do
      conn = conn(:get, "/api/authors/listing/all-authors") |> call()

      assert conn.status == 200
      body = decoded(conn)

      assert %{
               "isSuccess" => true,
               "isReady" => true,
               "data" => [%{"id" => @id, "name" => "Ada"}, _]
             } = body

      assert %{"paging" => %{"totalItems" => 2, "size" => 0}} = body
    end

    test "GET converts arguments and returns a single model" do
      conn = conn(:get, "/api/authors/listing/by-id?id=#{@id}") |> call()

      assert %{"data" => %{"name" => "Ada"}} = decoded(conn)
    end

    test "a missing required argument is a malformedRequest 400" do
      conn = conn(:get, "/api/authors/listing/by-id") |> call()

      assert conn.status == 400
      assert %{"validationResults" => [%{"reason" => "malformedRequest"}]} = decoded(conn)
    end

    test "paging and sorting via reserved query parameters" do
      conn =
        conn(
          :get,
          "/api/authors/listing/all-authors?page=0&pageSize=1&sortBy=name&sortDirection=desc"
        )
        |> call()

      body = decoded(conn)
      assert [%{"name" => "Bob"}] = body["data"]
      assert %{"page" => 0, "size" => 1, "totalItems" => 2, "totalPages" => 2} = body["paging"]
    end

    test "reserved parameters are matched case-insensitively and an invalid direction is rejected" do
      conn = conn(:get, "/api/authors/listing/all-authors?PAGESIZE=1&SORTBY=name") |> call()
      assert [%{"name" => "Ada"}] = decoded(conn)["data"]

      conn = conn(:get, "/api/authors/listing/all-authors?sortDirection=sideways") |> call()
      assert conn.status == 400
    end

    test "the QUERY method takes a JSON body and is not cacheable" do
      body = %{
        "arguments" => %{},
        "paging" => %{"page" => 1, "pageSize" => 1},
        "sorting" => %{"field" => "name", "direction" => "asc"}
      }

      conn =
        conn("QUERY", "/api/authors/listing/all-authors", Jason.encode!(body))
        |> put_req_header("content-type", "application/json")
        |> call()

      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert [%{"name" => "Bob"}] = decoded(conn)["data"]
    end

    test "QUERY rejects non-map arguments, paging and sorting" do
      for field <- ["arguments", "paging", "sorting"] do
        request =
          conn("QUERY", "/api/authors/listing/all-authors", Jason.encode!(%{field => []}))
          |> put_req_header("content-type", "application/json")
          |> call()

        assert request.status == 400

        assert [%{"message" => "The QUERY body is not valid."}] =
                 decoded(request)["validationResults"]
      end
    end

    test "a query with its own authorization answers 403 to an anonymous caller" do
      conn = conn(:get, "/api/authors/listing/secret-authors") |> call()
      assert conn.status == 403
    end
  end

  describe "introspection" do
    test "the catalogs require an authenticated caller by default" do
      assert (conn(:get, "/.cratis/commands") |> call()).status == 401
    end

    test "lists commands with route, summary and payload schema" do
      conn =
        conn(:get, "/.cratis/commands") |> assign(:arc_principal, Arc.Test.principal()) |> call()

      assert conn.status == 200

      assert %{
               "name" => "RegisterAuthor",
               "route" => @register,
               "documentationSummary" => "Registers a new author.",
               "payloadSchema" => %{
                 "required" => required,
                 "properties" => %{"id" => %{"format" => "uuid"}}
               }
             } = Enum.find(decoded(conn), &(&1["name"] == "RegisterAuthor"))

      assert "name" in required
    end

    test "lists queries with their fully qualified name" do
      conn =
        conn(:get, "/.cratis/queries") |> assign(:arc_principal, Arc.Test.principal()) |> call()

      assert Enum.any?(
               decoded(conn),
               &(&1["fullyQualifiedName"] == "ArcFixtures.Authors.Listing.Authors.AllAuthors")
             )
    end
  end
end
