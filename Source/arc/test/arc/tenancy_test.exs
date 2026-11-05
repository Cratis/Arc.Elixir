# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.TenancyTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Arc.{Principal, Tenancy}

  defp resolve(conn, tenancy, principal \\ Principal.anonymous(), config \\ []),
    do: Tenancy.resolve(conn, principal, Keyword.put(config, :tenancy, tenancy))

  defp on(host), do: %{conn(:get, "/") | host: host}

  describe "header" do
    test "is the default and reads x-cratis-tenant-id" do
      conn = conn(:get, "/") |> Plug.Conn.put_req_header("x-cratis-tenant-id", "acme")
      assert resolve(conn, []) == "acme"
      assert resolve(conn(:get, "/"), []) == nil
    end

    test "can be renamed through the tenancy options or the legacy tenant_header" do
      conn = conn(:get, "/") |> Plug.Conn.put_req_header("x-tenant", "acme")
      assert resolve(conn, header: "X-Tenant") == "acme"
      assert resolve(conn, [], Principal.anonymous(), tenant_header: "x-tenant") == "acme"
    end

    test "a blank header is no tenant" do
      conn = conn(:get, "/") |> Plug.Conn.put_req_header("x-cratis-tenant-id", "  ")
      assert resolve(conn, []) == nil
    end
  end

  test "query reads the configured parameter" do
    assert resolve(conn(:get, "/?tenantId=acme"), resolver: :query) == "acme"

    assert resolve(conn(:get, "/?tenant=beta"), resolver: :query, query_parameter: "tenant") ==
             "beta"

    assert resolve(conn(:get, "/"), resolver: :query) == nil
  end

  test "claim reads the principal and does not check anything else" do
    principal = Principal.new("1", "Ada", claims: %{"tenant_id" => "acme"})
    assert resolve(conn(:get, "/"), [resolver: :claim], principal) == "acme"
    assert resolve(conn(:get, "/"), [resolver: :claim, claim_type: "org"], principal) == nil
    assert resolve(conn(:get, "/"), [resolver: :claim], Principal.anonymous()) == nil
  end

  test "fixed and development always answer the configured tenant" do
    assert resolve(conn(:get, "/"), resolver: :fixed, tenant_id: "acme") == "acme"
    assert resolve(conn(:get, "/"), resolver: :development) == "development"
  end

  describe "subdomain" do
    @config [resolver: :subdomain, base_domain: "myapp.com"]

    test "exactly one label in front of the base domain is the tenant" do
      assert resolve(on("acme.myapp.com"), @config) == "acme"
      assert resolve(on("ACME.MyApp.com."), @config) == "acme"
      assert resolve(on("acme.myapp.com:5000"), @config) == "acme"
    end

    test "every other host falls back to the header" do
      header = fn host ->
        on(host) |> Plug.Conn.put_req_header("x-cratis-tenant-id", "fallback")
      end

      for host <- [
            "myapp.com",
            "acme.staging.myapp.com",
            "10.0.0.5",
            "otherapp.com",
            "evil-myapp.com",
            "acme.myapp.com.evil.com",
            "a_b.myapp.com"
          ] do
        assert resolve(header.(host), @config) == "fallback", host
      end
    end

    test "unicode lookalikes of the separators and ignorable characters match the same tenant" do
      assert resolve(on("admin。myapp.com"), @config) == "admin"
      assert resolve(on("ad\u200Bmin.myapp.com"), @config) == "admin"
      assert resolve(on("ａdmin.myapp.com"), @config) == "admin"
    end

    test "the base domain is required and must be a registrable domain" do
      for base <- [nil, "", "localhost", "X-Tenant-Id", "192.168.1.10", "com"] do
        assert_raise ArgumentError, fn ->
          Tenancy.validate!(tenancy: [resolver: :subdomain, base_domain: base])
        end
      end

      assert :ok = Tenancy.validate!(tenancy: @config)
    end
  end

  test "a module can resolve the tenant" do
    defmodule FromSession do
      @behaviour Arc.Tenancy
      @impl true
      def resolve(_conn, principal, _options), do: principal.name
    end

    principal = Principal.new("1", "from-name")
    assert resolve(conn(:get, "/"), [resolver: FromSession], principal) == "from-name"
  end

  describe "default tenant" do
    test "nil, empty and Default are the default" do
      assert Tenancy.default?(nil)
      assert Tenancy.default?("")
      assert Tenancy.default?("Default")
      refute Tenancy.default?("acme")
    end

    test "a named tenant selects the Chronicle namespace unless one is given" do
      assert Tenancy.chronicle_options([client: :c], "acme") == [namespace: "acme", client: :c]
      assert Tenancy.chronicle_options([client: :c], nil) == [client: :c]
      assert Tenancy.chronicle_options([namespace: "x"], "acme") == [namespace: "x"]
    end
  end
end
