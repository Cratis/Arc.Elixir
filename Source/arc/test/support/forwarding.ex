# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ArcFixtures.Forwarding do
  @moduledoc false

  # An independent implementation of the signed forwarded identity wire contract and of the
  # on-behalf assertion, written from the specification, used to sign requests in specs.

  @prefix "Cratis.AuthProxy.ForwardedIdentity.v1\n"
  @signature_header "x-cratis-forwarded-identity-signature"

  def vector_key, do: :binary.list_to_bin(Enum.to_list(0..31))

  def vector_principal_json,
    do: ~s({"identityProvider":"aad","userId":"u","userDetails":"n","userRoles":[],"claims":[]})

  def b64url(bytes), do: Base.url_encode64(bytes, padding: false)

  def frame(value), do: "#{byte_size(value)}:#{value}\n"

  @doc "Builds the signature envelope for `headers` (a map of lowercase name => value)."
  def envelope(key, opts) do
    audience = Keyword.fetch!(opts, :audience)
    kid = Keyword.get(opts, :kid, "k1")
    ts = Keyword.fetch!(opts, :ts) |> Integer.to_string()
    nonce = Keyword.fetch!(opts, :nonce)
    method = Keyword.get(opts, :method, "POST")
    target = Keyword.fetch!(opts, :target)
    headers = Keyword.fetch!(opts, :headers)

    path =
      target
      |> String.split("?", parts: 2)
      |> hd()
      |> String.replace(~r/%[0-9a-fA-F]{2}/, &String.upcase/1)

    names = headers |> Map.keys() |> Enum.reject(&(&1 == @signature_header)) |> Enum.sort()

    canonical =
      [
        @prefix
        | Enum.map(
            [audience, kid, ts, nonce, method, path, Integer.to_string(length(names))],
            &frame/1
          )
      ] ++
        Enum.flat_map(names, fn name ->
          [frame(name), frame(headers[name] |> String.trim(" "))]
        end)

    mac = :crypto.mac(:hmac, :sha256, key, IO.iodata_to_binary(canonical))
    "v1.#{kid}.#{ts}.#{nonce}.#{b64url(mac)}"
  end

  def nonce(byte), do: b64url(:binary.copy(<<byte>>, 32))

  def principal_json(overrides \\ %{}) do
    Jason.encode!(
      Map.merge(
        %{
          "identityProvider" => "aad",
          "userId" => "u",
          "userDetails" => "n",
          "userRoles" => [],
          "claims" => []
        },
        overrides
      )
    )
  end

  # RSA

  def generate_keypair(bits \\ 2048) do
    private = :public_key.generate_key({:rsa, bits, 65_537})
    {:RSAPrivateKey, _version, modulus, exponent, _, _, _, _, _, _, _} = private
    public = {:RSAPublicKey, modulus, exponent}
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:SubjectPublicKeyInfo, public)])
    {private, pem}
  end

  def private_pem(private),
    do: :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private)])

  @doc "A compact RS256 JWS."
  def jws(claims, private, opts \\ []) do
    header =
      Map.merge(
        %{"alg" => "RS256", "kid" => "authproxy", "typ" => "JWT"},
        Map.new(Keyword.get(opts, :header, []))
      )

    input = b64url(Jason.encode!(header)) <> "." <> b64url(Jason.encode!(claims))
    signature = :public_key.sign(input, :sha256, private)
    input <> "." <> b64url(signature)
  end

  def sha256(value), do: b64url(:crypto.hash(:sha256, value))

  @doc "A valid set of on-behalf claims for the represented principal header and actor header."
  def claims(principal_header, actor_header, overrides \\ %{}) do
    now = System.os_time(:second)

    Map.merge(
      %{
        "iss" => "https://authproxy.example.com",
        "aud" => "https://app.example.com",
        "sub" => "u",
        "act" => %{"sub" => "support"},
        "principal_hash" => sha256(principal_header),
        "actor_hash" => sha256(actor_header),
        "purpose" => "on-behalf-forward",
        "nbf" => now - 1,
        "iat" => now - 1,
        "exp" => now + 60,
        "jti" => b64url(:crypto.strong_rand_bytes(12))
      },
      overrides
    )
  end

  def encode_principal(json), do: Base.encode64(json)
end
