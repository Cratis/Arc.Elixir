# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.IdentityTest do
  # Application configuration is global, so these specs are not async.
  use ExUnit.Case

  import Plug.Conn
  import Plug.Test

  @app ArcFixtures.App

  setup do
    previous = Application.get_env(:cratis_arc, @app)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cratis_arc, @app, previous),
        else: Application.delete_env(:cratis_arc, @app)

      Arc.Application.refresh(@app)
    end)

    :ok
  end

  defp configure(opts) do
    Application.put_env(:cratis_arc, @app, opts)
    Arc.Application.refresh(@app)
  end

  defp call(conn), do: Arc.Plug.call(conn, Arc.Plug.init(application: @app))
  defp signed_in(conn, principal), do: assign(conn, :arc_principal, principal)

  describe "/.cratis/me" do
    test "an anonymous caller is a 401 with no body and a private response" do
      conn = conn(:get, "/.cratis/me") |> call()

      assert conn.status == 401
      assert conn.resp_body == ""
      assert get_resp_header(conn, "cache-control") == ["no-store, private"]
      assert get_resp_header(conn, "vary") == ["cookie"]
    end

    test "a signed-in caller gets id, name, flags, roles and typed details" do
      principal =
        Arc.Principal.new("u1", "Ada",
          roles: ["editor"],
          claims: %{"department" => "Engineering"}
        )

      conn = conn(:get, "/.cratis/me") |> signed_in(principal) |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Enum.sort(Map.keys(body)) == ~w(details id isAuthenticated isAuthorized name roles)

      assert %{
               "id" => "u1",
               "name" => "Ada",
               "isAuthenticated" => true,
               "isAuthorized" => true,
               "roles" => ["editor"],
               "details" => %{"displayName" => "Hello Ada", "department" => "Engineering"}
             } = body

      assert get_resp_header(conn, "cache-control") == ["no-store, private"]
    end

    test "a provider can refuse an authenticated user with a 403" do
      conn = conn(:get, "/.cratis/me") |> signed_in(Arc.Principal.new("u2", "banned")) |> call()

      assert conn.status == 403
      assert conn.resp_body == ""
    end

    test "is not served when the application has no identity provider" do
      defmodule NoIdentityApp do
        use Arc.Application, otp_app: :cratis_arc, artifacts: []
      end

      conn = conn(:get, "/.cratis/me") |> Arc.Plug.call(Arc.Plug.init(application: NoIdentityApp))

      refute conn.halted
    end
  end

  describe "discovery routes" do
    test "the details schema describes the provider's declared type" do
      conn =
        conn(:get, "/.cratis/identity-details/schema")
        |> signed_in(Arc.Principal.new("u1", "Ada"))
        |> call()

      assert %{
               "type" => "object",
               "properties" => %{
                 "displayName" => %{"type" => "string"},
                 "department" => %{"type" => "string"}
               },
               "required" => ["displayName"]
             } = Jason.decode!(conn.resp_body)
    end

    test "users and tenants list what the providers contribute, privately" do
      principal = Arc.Principal.new("u1", "Ada")

      users = conn(:get, "/.cratis/users") |> signed_in(principal) |> call()
      tenants = conn(:get, "/.cratis/tenants") |> signed_in(principal) |> call()

      assert [
               %{
                 "microsoftIdentity" => %{
                   "identityProvider" => "dev",
                   "userId" => "ada@example.com",
                   "userDetails" => "Ada",
                   "userRoles" => ["editor"],
                   "claims" => [%{"typ" => "department", "val" => "Engineering"}]
                 },
                 "details" => %{"department" => "Engineering"}
               }
             ] = Jason.decode!(users.resp_body)

      assert [%{"id" => "acme", "name" => "ACME"}] = Jason.decode!(tenants.resp_body)
      assert get_resp_header(users.resp_body && users, "cache-control") == ["no-store, private"]
    end

    test "they follow the discovery access setting" do
      assert (conn(:get, "/.cratis/users") |> call()).status == 401
      assert (conn(:get, "/.cratis/identity-details/schema") |> call()).status == 401

      configure(introspection: :anonymous)
      assert (conn(:get, "/.cratis/users") |> call()).status == 200

      configure(introspection: false)
      refute (conn(:get, "/.cratis/users") |> call()).halted
    end
  end

  describe "Arc.Authentication.ClientPrincipal" do
    @payload %{
               identityProvider: "aad",
               userId: "alice@contoso.com",
               userDetails: "Alice",
               userRoles: ["anonymous", "authenticated"],
               claims: [%{typ: "department", val: "Engineering"}, %{typ: "roles", val: "editor"}]
             }
             |> Jason.encode!()
             |> Base.encode64()

    defp principal_conn(headers) do
      Enum.reduce(headers, conn(:get, "/.cratis/me"), fn {k, v}, conn ->
        put_req_header(conn, k, v)
      end)
    end

    test "ignores the unsigned headers unless the host trusts them" do
      configure(authentication: [Arc.Authentication.ClientPrincipal])

      conn = principal_conn([{"x-ms-client-principal", @payload}]) |> call()

      assert conn.status == 401
    end

    test "builds the principal from the headers when trusted" do
      configure(
        authentication: [Arc.Authentication.ClientPrincipal],
        trust_forwarded_identity_headers: true
      )

      conn =
        principal_conn([
          {"x-ms-client-principal", @payload},
          {"x-ms-client-principal-id", "UTF-8''alice%40contoso.com"},
          {"x-ms-client-principal-name", "Alice Developer"}
        ])
        |> call()

      assert conn.status == 200

      assert %{
               "id" => "alice@contoso.com",
               "name" => "Alice Developer",
               "roles" => roles,
               "details" => %{
                 "displayName" => "Hello Alice Developer",
                 "department" => "Engineering"
               }
             } = Jason.decode!(conn.resp_body)

      assert Enum.sort(roles) == ["anonymous", "authenticated", "editor"]
    end

    test "falls back to the principal's own fields" do
      configure(
        authentication: [Arc.Authentication.ClientPrincipal],
        trust_forwarded_identity_headers: true
      )

      conn = principal_conn([{"x-ms-client-principal", @payload}]) |> call()

      assert %{"id" => "alice@contoso.com", "name" => "Alice"} = Jason.decode!(conn.resp_body)
    end

    test "a payload that is not a client principal fails the request" do
      configure(
        authentication: [Arc.Authentication.ClientPrincipal],
        trust_forwarded_identity_headers: true
      )

      conn = principal_conn([{"x-ms-client-principal", "not-base64-json"}]) |> call()

      assert conn.status == 401
    end

    test "a request without the headers is left to the next handler" do
      configure(
        authentication: [Arc.Authentication.ClientPrincipal, Arc.Authentication.FromAssigns],
        trust_forwarded_identity_headers: true
      )

      conn = conn(:get, "/.cratis/me") |> signed_in(Arc.Principal.new("u1", "Ada")) |> call()

      assert conn.status == 200
    end
  end

  describe "Arc.Identity.resolve/2" do
    test "an anonymous principal is unauthenticated without calling the provider" do
      assert %Arc.Identity.Result{authenticated?: false} =
               Arc.Identity.resolve(@app, Arc.Principal.anonymous())
    end

    test "roles reach the provider as claims" do
      defmodule ClaimsProvider do
        use Arc.Identity.Provider

        @impl true
        def details(%Arc.Identity.Context{claims: claims}),
          do: {:ok, %{claims: Enum.map(claims, &Tuple.to_list/1)}}
      end

      configure(identity_details: ClaimsProvider)

      result = Arc.Identity.resolve(@app, Arc.Principal.new("u1", "Ada", roles: ["editor"]))

      assert result.details.claims == [["role", "editor"]]
    end
  end
end
