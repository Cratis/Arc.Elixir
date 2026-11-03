# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Identity.OnBehalfOf do
  @moduledoc """
  Acting on behalf of a user: verifies the RS256 assertion Cratis AuthProxy signs for an on-behalf
  session and attaches the actor to the represented user's principal.

  Inside such a request two identities matter. The **represented user** is the request principal,
  and decides what the request may do: roles, tenant and authorization are theirs. The **actor**
  is who actually acts, and is available as `principal.actor` and recorded by Chronicle as the
  cause of every event, on behalf of the represented user.

  The ingress forwards the usual `x-ms-client-principal*` headers plus `x-cratis-on-behalf-actor`
  (the actor's base64 client principal) and `x-cratis-on-behalf-assertion` (a compact RS256 JWS).
  Enable it with the `on_behalf_of` option, which also needs `trust_forwarded_identity_headers`:

      config :my_app, MyApp.Arc,
        trust_forwarded_identity_headers: true,
        on_behalf_of: [
          enabled: true,
          issuer: "https://authproxy.example.com",
          audience: "https://app.example.com",
          service: "portal",
          clock_skew: 30,
          signing_keys: [[key_id: "authproxy-2026", public_key_pem: "-----BEGIN PUBLIC KEY-----\\n..."]]
        ]

  `service` is optional: set it when the ingress fronts several services with the same keys,
  so an assertion issued for another service is refused. `clock_skew` is in seconds. Signing keys
  must be RSA public keys of at least 2048 bits in PEM form; a private key is refused so the
  signing secret never reaches configuration.

  Arc accepts a forward only when the assertion passes every check: RS256 with a configured `kid`
  and no `crit` header; the issuer; the audience; `nbf` and `exp` present, now within them allowing
  for the skew, and a lifetime of at most five minutes; the purpose `on-behalf-forward`; the service,
  when configured; `jti` present and not used before; the represented user's principal hash,
  subject and id header; the actor hash and subject; the tenant, when the request carries the
  tenant header; and `htm` and `htu`, when present. The actor must be a valid client principal
  whose `userId` differs from the represented user's.

  The replay check is in memory and per application process. With several nodes a captured
  assertion can be replayed once to each other node within its lifetime. The ingress must strip
  every inbound `x-cratis-on-behalf-*` and `x-ms-client-principal*` header.
  """

  alias Arc.Identity.{Forwarded, ReplayCache}

  @actor_header "x-cratis-on-behalf-actor"
  @assertion_header "x-cratis-on-behalf-assertion"
  @purpose "on-behalf-forward"
  @max_lifetime 300
  @min_key_bits 2048

  def actor_header, do: @actor_header
  def assertion_header, do: @assertion_header

  @doc "Whether the request carries either on-behalf header."
  @spec present?((String.t() -> boolean())) :: boolean()
  def present?(has_header), do: has_header.(@actor_header) or has_header.(@assertion_header)

  @doc """
  Whether on-behalf forwarding may be used at all: the host trusts forwarded identity headers and
  the feature is enabled. Returns `nil` or the failure.
  """
  @spec admit(keyword()) :: String.t() | nil
  def admit(config) do
    cond do
      config[:trust_forwarded_identity_headers] != true -> failure(:untrusted_forward)
      options(config)[:enabled] != true -> failure(:not_enabled)
      true -> nil
    end
  end

  @doc "Reads and validates the configured signing keys. `{:ok, %{key_id => rsa_public_key}}` or `{:error, problem}`."
  @spec signing_keys(keyword()) :: {:ok, map()} | {:error, String.t()}
  def signing_keys(config) do
    options = options(config)

    cond do
      blank?(options[:issuer]) or blank?(options[:audience]) ->
        {:error, "an issuer and an audience are required"}

      Enum.empty?(List.wrap(options[:signing_keys])) ->
        {:error, "at least one signing key is required"}

      true ->
        Enum.reduce_while(List.wrap(options[:signing_keys]), {:ok, %{}}, fn key, {:ok, acc} ->
          with {:ok, id, rsa} <- read_key(key),
               false <- Map.has_key?(acc, id) do
            {:cont, {:ok, Map.put(acc, id, rsa)}}
          else
            true ->
              {:halt,
               {:error, "the key identifier '#{key_id(key)}' is configured more than once"}}

            {:error, problem} ->
              {:halt, {:error, problem}}
          end
        end)
    end
  end

  defp read_key(key) do
    id = key_id(key)
    pem = get(key, :public_key_pem)

    cond do
      blank?(id) ->
        {:error, "every signing key needs a key identifier"}

      blank?(pem) ->
        {:error, "the signing key '#{id}' has no public key"}

      String.contains?(String.upcase(pem), "PRIVATE KEY") ->
        {:error, "the signing key '#{id}' is a private key - configure the public key only"}

      true ->
        parse_public_key(id, pem)
    end
  end

  defp parse_public_key(id, pem) do
    with [entry | _] <- safe(fn -> :public_key.pem_decode(pem) end),
         {:RSAPublicKey, modulus, _exponent} = rsa <-
           safe(fn -> :public_key.pem_entry_decode(entry) end) do
      if modulus_bits(modulus) < @min_key_bits,
        do: {:error, "the signing key '#{id}' is shorter than #{@min_key_bits} bits"},
        else: {:ok, id, rsa}
    else
      _ -> {:error, "the signing key '#{id}' is not an RSA public key in PEM form"}
    end
  end

  defp modulus_bits(modulus) do
    bytes = :binary.encode_unsigned(modulus)
    <<first, _::binary>> = bytes
    (byte_size(bytes) - 1) * 8 + trunc(:math.log2(first)) + 1
  end

  defp safe(fun) do
    fun.()
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  @doc """
  Verifies an on-behalf forward and returns the actor.

  `forward` is `%{principal:, principal_id:, actor:, assertion:, tenant:, method:, path:}` with the
  raw header values. `represented` is the represented user's principal. Returns `{:ok, actor,
  valid_until}` (unix seconds) or `{:error, reason}`.
  """
  @spec attach(
          map(),
          Arc.Principal.t(),
          module(),
          keyword(),
          {:ok, map()} | {:error, String.t()},
          integer()
        ) ::
          {:ok, Arc.Principal.t(), integer()} | {:error, String.t()}
  def attach(forward, %Arc.Principal{} = represented, app, config, keys, now) do
    options = options(config)
    skew = options[:clock_skew] || 30

    with nil <- admit(config),
         :ok <- repeated(forward),
         :ok <- present_value(forward.actor, :missing_actor),
         :ok <- present_value(forward.assertion, :missing_assertion),
         {:ok, key_map} <- keys_or_misconfigured(keys),
         {:ok, assertion} <- verify_assertion(forward.assertion, key_map, options, skew, now),
         :ok <- bind(assertion, forward, represented),
         {:ok, actor_client} <- read_actor(forward.actor),
         :ok <- actor_matches(actor_client, assertion, represented),
         :ok <- record(app, assertion, skew, now) do
      {:ok, Forwarded.to_principal(actor_client, actor_client.user_id), assertion.expires + skew}
    else
      reason when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp repeated(%{actor: actor, assertion: assertion}) do
    if contains_comma?(actor) or contains_comma?(assertion),
      do: {:error, failure(:repeated_header)},
      else: :ok
  end

  defp contains_comma?(nil), do: false
  defp contains_comma?(value), do: String.contains?(value, ",")

  defp present_value(value, reason),
    do: if(blank?(value), do: {:error, failure(reason)}, else: :ok)

  defp keys_or_misconfigured({:ok, keys}), do: {:ok, keys}

  defp keys_or_misconfigured({:error, problem}),
    do: {:error, "#{failure(:misconfigured)}: #{problem}"}

  # The assertion

  defp verify_assertion(token, keys, options, skew, now) do
    with [h, p, s] <- String.split(token, "."),
         {:ok, header_bytes} <- b64url(h),
         {:ok, payload_bytes} <- b64url(p),
         {:ok, signature} <- b64url(s),
         {:ok, %{} = header} <- Jason.decode(header_bytes),
         {:ok, %{} = payload} <- Jason.decode(payload_bytes) do
      with :ok <- verify_signature(header, "#{h}.#{p}", signature, keys) do
        verify_claims(payload, options, skew, now)
      end
    else
      _ -> {:error, failure(:malformed_assertion)}
    end
  end

  defp verify_signature(header, signed, signature, keys) do
    cond do
      Map.has_key?(header, "crit") ->
        {:error, failure(:malformed_assertion)}

      header["alg"] != "RS256" ->
        {:error, failure(:unsupported_algorithm)}

      not is_binary(header["kid"]) or header["kid"] == "" or not Map.has_key?(keys, header["kid"]) ->
        {:error, failure(:unknown_signing_key)}

      :public_key.verify(signed, :sha256, signature, Map.fetch!(keys, header["kid"])) ->
        :ok

      true ->
        {:error, failure(:invalid_signature)}
    end
  end

  defp verify_claims(payload, options, skew, now) do
    service = options[:service]

    with :ok <- check(payload["iss"] == options[:issuer], :invalid_issuer),
         :ok <- check(audience?(payload["aud"], options[:audience]), :invalid_audience),
         {:ok, nbf, exp} <- lifetime(payload, skew, now),
         :ok <- check(payload["purpose"] == @purpose, :wrong_purpose),
         :ok <- check(blank?(service) or payload["svc"] == service, :service_mismatch),
         :ok <- check(non_blank_string?(payload["jti"]), :missing_token_id),
         :ok <-
           check(
             non_blank_string?(payload["sub"]) and non_blank_string?(payload["principal_hash"]),
             :principal_mismatch
           ),
         actor_subject = actor_subject(payload["act"]),
         :ok <-
           check(
             non_blank_string?(actor_subject) and non_blank_string?(payload["actor_hash"]),
             :actor_mismatch
           ) do
      _ = nbf

      {:ok,
       %{
         subject: payload["sub"],
         actor_subject: actor_subject,
         tenant: string(payload["tenant"]),
         principal_hash: payload["principal_hash"],
         actor_hash: payload["actor_hash"],
         method: string(payload["htm"]),
         target: string(payload["htu"]),
         token_id: payload["jti"],
         expires: exp
       }}
    end
  end

  defp lifetime(payload, skew, now) do
    nbf = time(payload["nbf"])
    exp = time(payload["exp"])

    cond do
      is_nil(nbf) or is_nil(exp) ->
        {:error, failure(:missing_lifetime)}

      exp - min(time(payload["iat"]) || nbf, nbf) > @max_lifetime ->
        {:error, failure(:lifetime_too_long)}

      now + skew < nbf ->
        {:error, failure(:not_yet_valid)}

      now - skew >= exp ->
        {:error, failure(:expired)}

      true ->
        {:ok, nbf, exp}
    end
  end

  defp time(value) when is_number(value) and value >= 0, do: floor(value)
  defp time(_), do: nil

  defp audience?(value, audience) when is_binary(value), do: value == audience

  defp audience?(values, audience) when is_list(values),
    do: Enum.any?(values, &(is_binary(&1) and &1 == audience))

  defp audience?(_, _), do: false

  defp actor_subject(%{} = act), do: string(act["sub"])
  defp actor_subject(_), do: nil

  defp string(value) when is_binary(value), do: value
  defp string(_), do: nil

  # Binding to the request

  defp bind(assertion, forward, represented) do
    cond do
      not hash_matches?(assertion.principal_hash, forward.principal) or
        assertion.subject != represented.id or
          Forwarded.decode_header_value(forward.principal_id) != represented.id ->
        {:error, failure(:principal_mismatch)}

      not hash_matches?(assertion.actor_hash, forward.actor || "") ->
        {:error, failure(:actor_mismatch)}

      not blank?(forward.tenant) and assertion.tenant != forward.tenant ->
        {:error, failure(:tenant_mismatch)}

      assertion.method != nil and assertion.method != forward.method ->
        {:error, failure(:method_mismatch)}

      assertion.target != nil and not target_matches?(assertion.target, forward.path) ->
        {:error, failure(:target_mismatch)}

      true ->
        :ok
    end
  end

  defp hash_matches?(expected, header_value) do
    Plug.Crypto.secure_compare(
      expected,
      Base.url_encode64(:crypto.hash(:sha256, header_value), padding: false)
    )
  end

  defp target_matches?("/" <> _ = target, path) do
    with signed when is_binary(signed) <- normalize_path(target),
         received when is_binary(received) <- normalize_path(path) do
      signed == received
    else
      _ -> false
    end
  end

  defp target_matches?(_, _), do: false

  @doc false
  @spec normalize_path(String.t()) :: String.t() | nil
  def normalize_path(path), do: normalize_path(path, [])

  defp normalize_path(<<?%, a, b, rest::binary>>, acc) do
    with true <- hex?(a) and hex?(b),
         {octet, ""} <- Integer.parse(<<a, b>>, 16) do
      if octet == ?/,
        do: normalize_path(rest, ["%2F" | acc]),
        else: normalize_path(rest, [<<octet>> | acc])
    else
      _ -> normalize_path(<<a, b, rest::binary>>, ["%" | acc])
    end
  end

  defp normalize_path(<<c::utf8, rest::binary>>, acc),
    do: normalize_path(rest, [<<c::utf8>> | acc])

  defp normalize_path(<<_invalid, _::binary>>, _acc), do: nil

  defp normalize_path(<<>>, acc) do
    result = acc |> Enum.reverse() |> IO.iodata_to_binary()
    if String.valid?(result), do: result, else: nil
  end

  defp hex?(c), do: c in ?0..?9 or c in ?a..?f or c in ?A..?F

  # The actor

  defp read_actor(header) do
    case Forwarded.read_principal(header, strict: true) do
      {:ok, client} -> {:ok, client}
      :error -> {:error, failure(:invalid_actor)}
    end
  end

  defp actor_matches(actor, assertion, represented) do
    cond do
      actor.user_id != assertion.actor_subject -> {:error, failure(:actor_mismatch)}
      actor.user_id == represented.id -> {:error, failure(:actor_is_represented_user)}
      true -> :ok
    end
  end

  defp record(app, assertion, skew, now) do
    if ReplayCache.record_on_behalf(app, assertion.token_id, assertion.expires + skew, now),
      do: :ok,
      else: {:error, failure(:replayed)}
  end

  # Helpers

  defp b64url(value) do
    if value != "" and rem(byte_size(value), 4) != 1 and
         Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, value),
       do: Base.url_decode64(value, padding: false),
       else: :error
  end

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, failure(reason)}

  defp options(config), do: Keyword.get(config, :on_behalf_of, [])

  defp key_id(key), do: get(key, :key_id)
  defp get(key, name) when is_list(key), do: Keyword.get(key, name)
  defp get(key, name) when is_map(key), do: Map.get(key, name)
  defp get(_, _), do: nil

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
  defp non_blank_string?(value), do: is_binary(value) and value != ""

  @failures %{
    untrusted_forward:
      "Not authenticated - on-behalf forwarding requires trusted forwarded identity headers",
    not_enabled: "Not authenticated - on-behalf forwarding is not enabled on this host",
    misconfigured: "Not authenticated - on-behalf forwarding is misconfigured",
    missing_represented_user:
      "Not authenticated - on-behalf forward does not identify the represented user",
    repeated_header: "Not authenticated - an on-behalf header was repeated",
    missing_actor: "Not authenticated - on-behalf forward has an empty actor",
    invalid_actor: "Not authenticated - invalid representation of the on-behalf actor",
    actor_is_represented_user: "Not authenticated - an identity cannot act on behalf of itself",
    missing_assertion: "Not authenticated - on-behalf forward carries no assertion",
    malformed_assertion: "Not authenticated - the on-behalf assertion is malformed",
    unsupported_algorithm: "Not authenticated - the on-behalf assertion is not signed with RS256",
    unknown_signing_key:
      "Not authenticated - the on-behalf assertion is signed with an unknown key",
    invalid_signature: "Not authenticated - the on-behalf assertion signature is invalid",
    invalid_issuer: "Not authenticated - the on-behalf assertion has the wrong issuer",
    invalid_audience: "Not authenticated - the on-behalf assertion has the wrong audience",
    missing_lifetime: "Not authenticated - the on-behalf assertion has no nbf or exp",
    not_yet_valid: "Not authenticated - the on-behalf assertion is not yet valid",
    expired: "Not authenticated - the on-behalf assertion has expired",
    lifetime_too_long:
      "Not authenticated - the on-behalf assertion lives longer than five minutes",
    service_mismatch: "Not authenticated - the on-behalf assertion is for another service",
    wrong_purpose: "Not authenticated - the on-behalf assertion is not for a forwarded request",
    missing_token_id: "Not authenticated - the on-behalf assertion has no jti",
    principal_mismatch:
      "Not authenticated - the on-behalf assertion does not match the represented user's headers",
    actor_mismatch: "Not authenticated - the on-behalf assertion does not match the actor header",
    tenant_mismatch: "Not authenticated - the on-behalf assertion is for another tenant",
    method_mismatch: "Not authenticated - the on-behalf assertion is for another HTTP method",
    target_mismatch: "Not authenticated - the on-behalf assertion is for another target",
    replayed: "Not authenticated - the on-behalf assertion has already been used"
  }

  @doc false
  def failure(reason), do: Map.fetch!(@failures, reason)
end
