# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.SignedForwardingTest do
  # Replay memory belongs to the started application, which is registered by name.
  use ExUnit.Case

  import Plug.Conn
  import Plug.Test

  alias ArcFixtures.Forwarding, as: F
  alias Arc.Identity.SignedForwarding

  @app ArcFixtures.App
  @now 1_700_000_000
  @principal F.vector_principal_json() |> Base.encode64()

  @config [
    trust_forwarded_identity_headers: true,
    tenant_header: "x-cratis-tenant-id",
    forwarded_identity: [
      enabled: true,
      audience: "arc-test",
      keys: [[key_id: "k1", secret_base64: Base.encode64(F.vector_key())]]
    ]
  ]

  setup do
    start_supervised!(@app)
    :ok
  end

  defp headers(extra \\ %{}),
    do:
      Map.merge(
        %{
          "x-ms-client-principal" => @principal,
          "x-ms-client-principal-id" => "u",
          "x-ms-client-principal-name" => "n"
        },
        extra
      )

  defp signed(opts \\ []) do
    headers = Keyword.get(opts, :headers, headers())
    target = Keyword.get(opts, :target, "/base/a%2fb?x=1")

    signature =
      F.envelope(F.vector_key(),
        audience: Keyword.get(opts, :audience, "arc-test"),
        kid: Keyword.get(opts, :kid, "k1"),
        ts: Keyword.get(opts, :ts, @now),
        nonce: Keyword.get(opts, :nonce, F.nonce(0)),
        method: Keyword.get(opts, :method, "POST"),
        target: Keyword.get(opts, :signed_target, target),
        headers: headers
      )

    build(
      Keyword.get(opts, :method, "POST"),
      target,
      headers,
      Keyword.get(opts, :signature, signature)
    )
  end

  defp build(method, target, headers, signature) do
    base = conn(method, target)
    base = Enum.reduce(headers, base, fn {k, v}, c -> put_req_header(c, k, v) end)

    if signature,
      do: put_req_header(base, "x-cratis-forwarded-identity-signature", signature),
      else: base
  end

  defp authenticate(conn, now \\ @now),
    do: SignedForwarding.authenticate(conn, @app, @config, now)

  describe "the interoperability vector" do
    test "the documented MAC and envelope verify" do
      expected =
        "v1.k1.1700000000.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.jgVyScoemstnZgj25AE70omcBbrUuzl9bIoesbV_BHo"

      assert signed() |> get_req_header("x-cratis-forwarded-identity-signature") == [expected]
      assert {:authenticated, principal} = authenticate(signed())
      assert %{id: "u", name: "n", authenticated?: true} = principal
      assert principal.claims["urn:cratis:arc:identity:provider"] == "aad"
    end

    test "nonce B produces the second documented envelope, and both authenticate once" do
      expected =
        "v1.k1.1700000000.AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE.ql7vBinbDwBTqcRq5op-eA4hyMWHf0LFh5MqPlG6qsI"

      assert signed(nonce: F.nonce(1)) |> get_req_header("x-cratis-forwarded-identity-signature") ==
               [expected]

      assert {:authenticated, _} = authenticate(signed())
      assert {:authenticated, _} = authenticate(signed(nonce: F.nonce(1)))
    end

    test "header order, header name case and path escape case do not change the MAC" do
      conn = signed(target: "/base/a%2Fb?x=1", signed_target: "/base/a%2fb?x=1")
      conn = %{conn | req_headers: Enum.reverse(conn.req_headers)}

      assert {:authenticated, _} = authenticate(conn)
    end

    test "the query is not covered" do
      assert {:authenticated, _} =
               authenticate(signed(target: "/base/a%2fb?x=2", signed_target: "/base/a%2fb?x=1"))
    end
  end

  describe "rejection" do
    @rejected {:failed, "forwarded-identity-rejected"}
    @invalid {:failed, "forwarded-identity-invalid-input"}

    test "anything changed after signing is rejected" do
      signature = signed() |> get_req_header("x-cratis-forwarded-identity-signature") |> hd()

      for {name, value} <- [
            {"x-ms-client-principal",
             Base.encode64(F.principal_json(%{"userDetails" => "other"}))},
            {"x-ms-client-principal-id", "v"},
            {"x-ms-client-principal-name", "m"},
            {"x-cratis-tenant-id", "acme"},
            {"x-cratis-on-behalf-actor", "x"}
          ] do
        conn =
          signed()
          |> put_req_header(name, value)
          |> put_req_header("x-cratis-forwarded-identity-signature", signature)

        assert authenticate(conn) in [@rejected, @invalid],
               "#{name} changed after signing should be rejected"
      end
    end

    test "a different method, audience, key id or escaped path is rejected" do
      assert authenticate(signed(signed_target: "/base/other")) == @rejected
      assert authenticate(signed(audience: "other")) == @rejected
      assert authenticate(signed(kid: "k2")) == @rejected
      assert authenticate(%{signed() | method: "PUT"}) == @rejected
    end

    test "a path that differs only by an escape's meaning is rejected" do
      assert authenticate(signed(target: "/a/b", signed_target: "/a%2Fb")) == @rejected
    end

    test "multiple observed values, extra components, padding and unknown versions are invalid input" do
      good = signed() |> get_req_header("x-cratis-forwarded-identity-signature") |> hd()

      duplicated = %{
        signed()
        | req_headers: signed().req_headers ++ [{"x-ms-client-principal-id", "u"}]
      }

      assert authenticate(duplicated) == @invalid
      assert authenticate(signed(signature: good <> ".extra")) == @invalid

      assert authenticate(signed(signature: String.replace(good, "v1.", "v2.", global: false))) ==
               @invalid

      assert authenticate(signed(signature: good <> "=")) == @invalid
    end

    test "a subject that is not the principal's userId is rejected" do
      headers = headers(%{"x-ms-client-principal-id" => "someone-else"})
      assert authenticate(signed(headers: headers)) == @rejected
    end
  end

  describe "freshness and replay" do
    test "the freshness edges are inclusive" do
      for {ts, nonce} <- [{1_699_999_940, 10}, {1_700_000_030, 11}] do
        assert {:authenticated, _} = authenticate(signed(ts: ts, nonce: F.nonce(nonce)))
      end

      for {ts, nonce} <- [{1_699_999_939, 12}, {1_700_000_031, 13}] do
        assert authenticate(signed(ts: ts, nonce: F.nonce(nonce))) ==
                 {:failed, "forwarded-identity-rejected"}
      end
    end

    test "a nonce is accepted once" do
      assert {:authenticated, _} = authenticate(signed())
      assert authenticate(signed()) == {:failed, "forwarded-identity-rejected"}
    end

    test "an invalid attempt does not poison a nonce" do
      tampered = signed() |> put_req_header("x-ms-client-principal-name", "tampered")
      assert authenticate(tampered) == {:failed, "forwarded-identity-rejected"}
      assert {:authenticated, _} = authenticate(signed())
    end

    test "replay memory forgets a nonce after its lifetime" do
      assert {:authenticated, _} = authenticate(signed())

      assert {:authenticated, _} =
               authenticate(signed(ts: @now + 61, nonce: F.nonce(0)), @now + 121)
    end
  end

  describe "no unsigned fallback" do
    test "unsigned identity headers do not authenticate when signing is on" do
      conn = build("GET", "/.cratis/me", headers(), nil)
      assert authenticate(conn) == {:failed, "forwarded-identity-invalid-input"}
    end

    test "a request with no credential at all is anonymous" do
      assert authenticate(conn(:get, "/api/x")) == :anonymous
    end

    test "invalid configuration fails a credentialed request" do
      bad =
        Keyword.put(@config, :forwarded_identity,
          enabled: true,
          audience: "arc-test",
          keys: [[key_id: "k1", secret_base64: "short"]]
        )

      assert SignedForwarding.authenticate(signed(), @app, bad, @now) ==
               {:failed, "forwarded-identity-invalid-input"}
    end

    test "signing requires trusted forwarded identity headers" do
      untrusted = Keyword.put(@config, :trust_forwarded_identity_headers, false)

      assert SignedForwarding.authenticate(signed(), @app, untrusted, @now) ==
               {:failed, "forwarded-identity-invalid-input"}
    end
  end

  describe "the HTTP host" do
    setup do
      previous = Application.get_env(:cratis_arc, @app)

      Application.put_env(
        :cratis_arc,
        @app,
        Keyword.put(@config, :authentication, [Arc.Authentication.MicrosoftIdentityPlatform])
      )

      Arc.Application.refresh(@app)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:cratis_arc, @app, previous),
          else: Application.delete_env(:cratis_arc, @app)

        Arc.Application.refresh(@app)
      end)
    end

    defp call(conn), do: Arc.Plug.call(conn, Arc.Plug.init(application: @app))

    test "/.cratis/me serves a signed identity and refuses an unsigned one" do
      ts = System.os_time(:second)
      target = "/.cratis/me"
      hs = headers()

      signature =
        F.envelope(F.vector_key(),
          audience: "arc-test",
          ts: ts,
          nonce: F.nonce(7),
          method: "GET",
          target: target,
          headers: hs
        )

      ok = build("GET", target, hs, signature) |> call()
      refused = build("GET", target, hs, nil) |> call()

      assert ok.status == 200

      assert %{"id" => "u", "name" => "n", "isAuthenticated" => true} =
               Jason.decode!(ok.resp_body)

      assert refused.status == 401
    end
  end
end
