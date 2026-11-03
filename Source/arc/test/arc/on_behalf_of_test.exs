# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.OnBehalfOfTest do
  # Replay memory belongs to the started application, which is registered by name.
  use ExUnit.Case

  import Plug.Conn
  import Plug.Test

  alias ArcFixtures.Forwarding, as: F
  alias Arc.Identity.{Forwarded, OnBehalfOf}

  @app ArcFixtures.App

  setup_all do
    {private, pem} = F.generate_keypair()
    {other, _} = F.generate_keypair()
    %{private: private, pem: pem, other: other}
  end

  setup %{pem: pem} do
    start_supervised!(@app)

    config = [
      trust_forwarded_identity_headers: true,
      tenant_header: "x-cratis-tenant-id",
      on_behalf_of: [
        enabled: true,
        issuer: "https://authproxy.example.com",
        audience: "https://app.example.com",
        service: "",
        clock_skew: 30,
        signing_keys: [[key_id: "authproxy", public_key_pem: pem]]
      ]
    ]

    %{config: config}
  end

  @represented F.principal_json(%{
                 "userId" => "u",
                 "userDetails" => "Ada",
                 "userRoles" => ["editor"]
               })
  @actor F.principal_json(%{
           "userId" => "support",
           "userDetails" => "Support Person",
           "userRoles" => ["support"]
         })

  # A forward as the ingress would send it, signed by `private`, with claim and header overrides.
  defp forward(private, opts \\ []) do
    principal = Keyword.get(opts, :principal, Base.encode64(@represented))
    actor = Keyword.get(opts, :actor, Base.encode64(@actor))

    claims = F.claims(principal, actor, Map.new(Keyword.get(opts, :claims, [])))
    claims = Enum.reduce(Keyword.get(opts, :drop, []), claims, &Map.delete(&2, &1))

    assertion =
      Keyword.get_lazy(opts, :assertion, fn ->
        F.jws(claims, Keyword.get(opts, :signer, private), header: Keyword.get(opts, :header, []))
      end)

    %{
      principal: principal,
      principal_id: Keyword.get(opts, :principal_id, "u"),
      actor: actor,
      assertion: assertion,
      tenant: Keyword.get(opts, :tenant),
      method: Keyword.get(opts, :method, "POST"),
      path: Keyword.get(opts, :path, "/api/things")
    }
  end

  defp represented,
    do:
      Forwarded.to_principal(
        elem(Forwarded.read_principal(Base.encode64(@represented), strict: true), 1),
        "u"
      )

  defp attach(forward, config),
    do:
      OnBehalfOf.attach(
        forward,
        represented(),
        @app,
        config,
        OnBehalfOf.signing_keys(config),
        System.os_time(:second)
      )

  defp rejected(forward, config, reason) do
    assert {:error, message} = attach(forward, config)
    assert message == OnBehalfOf.failure(reason)
  end

  describe "a verified forward" do
    test "attaches the actor to the represented user", %{private: private, config: config} do
      assert {:ok, actor, valid_until} = attach(forward(private), config)

      assert %{id: "support", name: "Support Person", roles: ["support"], authenticated?: true} =
               actor

      assert valid_until > System.os_time(:second)
      refute "support" in represented().roles
    end

    test "accepts an audience list, a matching tenant, method and target", %{
      private: private,
      config: config
    } do
      claims = [
        {"aud", ["other", "https://app.example.com"]},
        {"tenant", "acme"},
        {"htm", "POST"},
        {"htu", "/api/things"}
      ]

      assert {:ok, _, _} = attach(forward(private, claims: claims, tenant: "acme"), config)
    end

    test "tolerates clock skew at the edges", %{private: private, config: config} do
      now = System.os_time(:second)

      assert {:ok, _, _} =
               attach(
                 forward(private,
                   claims: [{"nbf", now + 20}, {"iat", now + 20}, {"exp", now + 70}]
                 ),
                 config
               )
    end

    test "compares paths after percent-decoding, except an encoded slash", %{
      private: private,
      config: config
    } do
      assert {:ok, _, _} =
               attach(
                 forward(private, claims: [{"htu", "/a%2Fb/c d"}], path: "/a%2fb/c%20d"),
                 config
               )

      rejected(
        forward(private, claims: [{"htu", "/a%2Fb"}], path: "/a/b"),
        config,
        :target_mismatch
      )

      rejected(
        forward(private, claims: [{"htu", "https://app.example.com/api/things"}]),
        config,
        :target_mismatch
      )
    end
  end

  describe "the assertion" do
    test "is verified: signature, algorithm, key and shape", %{
      private: private,
      other: other,
      config: config
    } do
      rejected(forward(private, signer: other), config, :invalid_signature)
      rejected(forward(private, header: [{"alg", "HS256"}]), config, :unsupported_algorithm)
      rejected(forward(private, header: [{"kid", "unknown"}]), config, :unknown_signing_key)
      rejected(forward(private, header: [{"crit", ["x"]}]), config, :malformed_assertion)
      rejected(forward(private, assertion: "a.b"), config, :malformed_assertion)
      rejected(forward(private, assertion: "!!.!!.!!"), config, :malformed_assertion)
    end

    test "is verified: issuer, audience, purpose, service and token id", %{
      private: private,
      config: config
    } do
      rejected(forward(private, claims: [{"iss", "https://evil"}]), config, :invalid_issuer)
      rejected(forward(private, claims: [{"aud", "elsewhere"}]), config, :invalid_audience)
      rejected(forward(private, claims: [{"purpose", "login"}]), config, :wrong_purpose)
      rejected(forward(private, drop: ["jti"]), config, :missing_token_id)

      with_service = put_in(config, [:on_behalf_of, :service], "portal")
      rejected(forward(private, claims: [{"svc", "billing"}]), with_service, :service_mismatch)
      assert {:ok, _, _} = attach(forward(private, claims: [{"svc", "portal"}]), with_service)
    end

    test "is verified: lifetime", %{private: private, config: config} do
      now = System.os_time(:second)

      rejected(forward(private, drop: ["nbf"]), config, :missing_lifetime)
      rejected(forward(private, drop: ["exp"]), config, :missing_lifetime)

      rejected(
        forward(private, claims: [{"nbf", now + 120}, {"iat", now + 120}, {"exp", now + 180}]),
        config,
        :not_yet_valid
      )

      rejected(
        forward(private, claims: [{"nbf", now - 200}, {"iat", now - 200}, {"exp", now - 100}]),
        config,
        :expired
      )

      rejected(
        forward(private, claims: [{"nbf", now - 1}, {"iat", now - 1}, {"exp", now + 400}]),
        config,
        :lifetime_too_long
      )

      rejected(
        forward(private, claims: [{"nbf", now}, {"iat", now - 400}, {"exp", now + 10}]),
        config,
        :lifetime_too_long
      )
    end

    test "is bound to the headers, the tenant, the method and the target", %{
      private: private,
      config: config
    } do
      rejected(
        forward(private,
          principal:
            Base.encode64(F.principal_json(%{"userId" => "u", "userDetails" => "Mallory"})),
          claims: [{"principal_hash", F.sha256(Base.encode64(@represented))}]
        ),
        config,
        :principal_mismatch
      )

      rejected(forward(private, principal_id: "other"), config, :principal_mismatch)
      rejected(forward(private, claims: [{"sub", "someone"}]), config, :principal_mismatch)

      rejected(
        forward(private, claims: [{"act", %{"sub" => "someone"}}]),
        config,
        :actor_mismatch
      )

      rejected(
        forward(private,
          actor:
            Base.encode64(F.principal_json(%{"userId" => "support", "userDetails" => "Other"})),
          claims: [{"actor_hash", F.sha256(Base.encode64(@actor))}]
        ),
        config,
        :actor_mismatch
      )

      rejected(
        forward(private, claims: [{"tenant", "acme"}], tenant: "globex"),
        config,
        :tenant_mismatch
      )

      rejected(forward(private, claims: [{"htm", "GET"}]), config, :method_mismatch)
      rejected(forward(private, claims: [{"htu", "/api/other"}]), config, :target_mismatch)
    end

    test "is accepted once", %{private: private, config: config} do
      forward = forward(private)

      assert {:ok, _, _} = attach(forward, config)
      rejected(forward, config, :replayed)
    end
  end

  describe "the actor" do
    test "must be a valid client principal", %{private: private, config: config} do
      rejected(forward(private, actor: "not base64!"), config, :invalid_actor)
    end

    test "cannot be the represented user", %{private: private, config: config} do
      same = Base.encode64(F.principal_json(%{"userId" => "u", "userDetails" => "Ada"}))

      rejected(
        forward(private, actor: same, claims: [{"act", %{"sub" => "u"}}]),
        config,
        :actor_is_represented_user
      )
    end

    test "headers must be present once", %{private: private, config: config} do
      rejected(%{forward(private) | actor: ""}, config, :missing_actor)
      rejected(%{forward(private) | assertion: ""}, config, :missing_assertion)
      rejected(%{forward(private) | actor: "a,b"}, config, :repeated_header)
    end
  end

  describe "admission and configuration" do
    test "requires trusted forwarded identity headers and the feature", %{
      private: private,
      config: config
    } do
      rejected(
        forward(private),
        Keyword.put(config, :trust_forwarded_identity_headers, false),
        :untrusted_forward
      )

      rejected(forward(private), put_in(config, [:on_behalf_of, :enabled], false), :not_enabled)
    end

    test "refuses unusable signing keys", %{private: private, pem: pem, config: config} do
      {small, small_pem} = F.generate_keypair(1024)

      for {keys, problem} <- [
            {[], "at least one signing key is required"},
            {[[key_id: "authproxy", public_key_pem: F.private_pem(private)]], "is a private key"},
            {[[key_id: "authproxy", public_key_pem: small_pem]], "shorter than 2048 bits"},
            {[[key_id: "authproxy", public_key_pem: "nonsense"]], "not an RSA public key"},
            {[[key_id: "", public_key_pem: pem]], "needs a key identifier"},
            {[
               [key_id: "authproxy", public_key_pem: pem],
               [key_id: "authproxy", public_key_pem: pem]
             ], "more than once"}
          ] do
        cfg = put_in(config, [:on_behalf_of, :signing_keys], keys)
        assert {:error, message} = attach(forward(private), cfg)
        assert message =~ OnBehalfOf.failure(:misconfigured)
        assert message =~ problem
      end

      _ = small
    end
  end

  describe "the authentication handler" do
    setup %{config: config} do
      previous = Application.get_env(:cratis_arc, @app)

      Application.put_env(
        :cratis_arc,
        @app,
        Keyword.put(config, :authentication, [Arc.Authentication.MicrosoftIdentityPlatform])
      )

      Arc.Application.refresh(@app)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:cratis_arc, @app, previous),
          else: Application.delete_env(:cratis_arc, @app)

        Arc.Application.refresh(@app)
      end)
    end

    defp authenticate(conn) do
      conn
      |> put_private(:arc_application, @app)
      |> Arc.Authentication.MicrosoftIdentityPlatform.authenticate()
    end

    defp request(forward) do
      conn(:post, "/api/things")
      |> put_req_header("x-ms-client-principal", forward.principal)
      |> put_req_header("x-ms-client-principal-id", forward.principal_id)
      |> put_req_header("x-ms-client-principal-name", "Ada")
      |> put_req_header("x-cratis-on-behalf-actor", forward.actor)
      |> put_req_header("x-cratis-on-behalf-assertion", forward.assertion)
    end

    test "authenticates the represented user with the actor attached", %{private: private} do
      assert {:authenticated, principal} = request(forward(private)) |> authenticate()

      assert %{id: "u", name: "Ada", roles: ["editor"]} = principal
      assert %{id: "support", name: "Support Person"} = principal.actor
      assert Arc.Principal.acted_on_behalf_of?(principal)
    end

    test "a forward that fails verification fails authentication, never falling back", %{
      private: private,
      other: other
    } do
      assert request(forward(private, signer: other)) |> authenticate() == :failed
    end

    test "an actor header without the represented user's headers fails", %{private: private} do
      conn =
        conn(:post, "/api/things")
        |> put_req_header("x-cratis-on-behalf-actor", forward(private).actor)

      assert authenticate(conn) == :failed
    end

    test "a plain forwarded request has no actor", %{private: _} do
      conn =
        conn(:post, "/api/things")
        |> put_req_header("x-ms-client-principal", Base.encode64(@represented))
        |> put_req_header("x-ms-client-principal-id", "u")
        |> put_req_header("x-ms-client-principal-name", "Ada")

      assert {:authenticated, %{actor: nil}} = authenticate(conn)
    end
  end
end
