# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Identity.SignedForwarding do
  @moduledoc """
  Signed forwarded identity: an ingress attests the identity headers it sends with an
  HMAC-SHA256 over the request, so the headers are no longer trusted merely because they are present.

  It is opt-in. Set `trust_forwarded_identity_headers: true` and `forwarded_identity: [enabled: true, …]`:

      config :my_app, MyApp.Arc,
        trust_forwarded_identity_headers: true,
        forwarded_identity: [
          enabled: true,
          audience: "my-app",
          keys: [[key_id: "k1", secret_base64: System.fetch_env!("ARC_FORWARDED_IDENTITY_KEY")]]
        ]

  Each secret is exactly 32 random bytes, standard-base64 encoded; configure 1 to 8 keys with
  distinct, case-sensitive ids, from your secret provider, never from a committed file. With signing
  enabled there is no unsigned fallback: a missing, malformed, expired, replayed or incorrectly signed
  credential establishes no identity, name, roles or actor.

  ## The wire contract

  The ingress sends exactly one `x-cratis-forwarded-identity-signature` value, `v1.<kid>.<ts>.<nonce>.<mac>`,
  at most 256 ASCII bytes: `kid` matches `[A-Za-z0-9_-]{1,64}`, `ts` is decimal Unix seconds, `nonce` is
  unpadded base64url of 32 fresh random bytes, and `mac` is unpadded base64url of the 32-byte
  HMAC-SHA256 over the canonical bytes. The canonical bytes start with
  `Cratis.AuthProxy.ForwardedIdentity.v1\\n` followed by frames `F(s)` (the UTF-8 byte count, `:`, the
  string, a line feed) for the audience, key id, timestamp, nonce, method, escaped path, the covered
  header count, and each covered header's lowercase name and value in ordinal order. Covered headers
  are every `x-ms-client-principal*` and `x-cratis-on-behalf*` header, `x-cratis-token-client-id`,
  `x-cratis-token-scope`, `x-cratis-tenant-id`, `tenant-id`, `x-cratis-microservice`, `service-id`
  and the configured tenant header. Every covered header must have exactly one value. The method and
  the path (with percent-escape hex digits uppercased) are bound; the query and body are not.

  A timestamp is accepted from 60 seconds in the past to 30 seconds in the future. The nonce is
  reserved only after the MAC and the identity bindings succeed, so an invalid attempt cannot poison it.
  Replay memory is per application process, like Arc on .NET: it is not shared across nodes or restarts.
  The application must be started (`MyApp.Arc` in the supervision tree); without it replays cannot be
  detected and every signed request is rejected.

  This attests identity and bindings, not tenant existence, tenant membership, request-body integrity
  or authorization. Use TLS and restrict backend ingress; a shared-key verifier can also forge
  identities, so provision service-specific secrets.
  """

  alias Arc.Identity.{Forwarded, OnBehalfOf, ReplayCache}

  @header "x-cratis-forwarded-identity-signature"
  @principal_header "x-ms-client-principal"
  @id_header "x-ms-client-principal-id"
  @name_header "x-ms-client-principal-name"
  @canonical_prefix "Cratis.AuthProxy.ForwardedIdentity.v1\n"
  @max_canonical 32_768

  def header, do: @header

  @doc "Whether any header carries a forwarded-identity credential."
  @spec credential?([String.t()]) :: boolean()
  def credential?(names) do
    Enum.any?(names, fn name ->
      name = String.downcase(name)

      name == @header or String.starts_with?(name, @principal_header) or
        String.starts_with?(name, "x-cratis-on-behalf")
    end)
  end

  @doc """
  Authenticates a connection. Returns `{:authenticated, principal}`, `:anonymous` (no credential),
  or `{:failed, reason}` with a fixed reason code.
  """
  @spec authenticate(Plug.Conn.t(), module(), keyword(), integer() | nil) ::
          {:authenticated, Arc.Principal.t()} | :anonymous | {:failed, String.t()}
  def authenticate(conn, app, config, now \\ nil) do
    now = now || System.os_time(:second)
    observed = capture(conn, config)

    authenticate_observed(observed, %{app: app, config: config, now: now})
  end

  defp authenticate_observed(nil, _context),
    do: {:failed, "forwarded-identity-invalid-input"}

  defp authenticate_observed(observed, context) do
    if credential?(Map.keys(observed.headers)),
      do: authenticate_credential(observed, context),
      else: :anonymous
  end

  defp authenticate_credential(observed, context) do
    with %{} = configuration <- configuration(context.config),
         signature when is_binary(signature) <- observed.headers[@header],
         %{} = envelope <- parse_envelope(signature),
         %{} = request <- canonicalize(observed, configuration, envelope) do
      verify_and_build(request, envelope, configuration, context)
    else
      _ -> {:failed, "forwarded-identity-invalid-input"}
    end
  end

  # Configuration

  @doc false
  @spec configuration(keyword()) :: map() | nil
  def configuration(config) do
    options = Keyword.get(config, :forwarded_identity, [])
    audience = options[:audience]
    keys = options[:keys]

    with true <- config[:trust_forwarded_identity_headers] == true and options[:enabled] == true,
         true <-
           is_binary(audience) and String.trim(audience) != "" and String.length(audience) <= 128,
         true <- audience |> String.to_charlist() |> Enum.all?(&(&1 >= ?\s and &1 < 127)),
         true <- is_list(keys) and length(keys) in 1..8,
         {:ok, parsed} <- parse_keys(keys) do
      %{audience: audience, keys: parsed, tenant_header: config[:tenant_header]}
    else
      _ -> nil
    end
  end

  defp parse_keys(keys) do
    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, acc} ->
      id = fetch(key, :key_id)
      secret = fetch(key, :secret_base64)

      with true <- key_id?(id) and is_binary(secret) and byte_size(secret) == 44,
           {:ok, bytes} <- Base.decode64(secret),
           true <- byte_size(bytes) == 32 and Base.encode64(bytes) == secret,
           false <- Map.has_key?(acc, id) do
        {:cont, {:ok, Map.put(acc, id, bytes)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp fetch(key, name) when is_list(key), do: Keyword.get(key, name)
  defp fetch(key, name) when is_map(key), do: Map.get(key, name)
  defp fetch(_, _), do: nil

  defp key_id?(id), do: is_binary(id) and Regex.match?(~r/\A[A-Za-z0-9_-]{1,64}\z/, id)

  # Observing the request

  # Only the covered headers (and the signature) are captured, each with exactly one observed value.
  defp capture(conn, config) do
    tenant_header = config[:tenant_header]

    grouped =
      conn.req_headers
      |> Enum.map(fn {name, value} -> {String.downcase(name), value} end)
      |> Enum.filter(fn {name, _} -> name == @header or covered?(name, tenant_header) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    with true <- map_size(grouped) <= 65,
         true <-
           Enum.all?(grouped, fn {name, values} ->
             match?([value] when byte_size(value) <= 32_768, values) and byte_size(name) <= 32_768
           end) do
      %{
        headers: Map.new(grouped, fn {name, [value]} -> {name, value} end),
        method: conn.method,
        raw_target: raw_target(conn)
      }
    else
      _ -> nil
    end
  end

  defp raw_target(%{request_path: path, query_string: ""}), do: path
  defp raw_target(%{request_path: path, query_string: query}), do: path <> "?" <> query

  defp covered?(name, tenant_header) do
    String.starts_with?(name, "x-ms-client-principal") or
      String.starts_with?(name, "x-cratis-on-behalf") or
      name in ~w(x-cratis-token-client-id x-cratis-token-scope x-cratis-tenant-id tenant-id x-cratis-microservice service-id) or
      (is_binary(tenant_header) and name == String.downcase(tenant_header))
  end

  # The envelope

  @doc false
  @spec parse_envelope(String.t()) :: map() | nil
  def parse_envelope(value) do
    with true <- byte_size(value) in 1..256 and ascii?(value),
         [version, kid, ts_text, nonce_text, mac_text] <- String.split(value, "."),
         true <- version == "v1" and key_id?(kid) and valid_timestamp_text?(ts_text),
         {timestamp, ""} <- Integer.parse(ts_text),
         true <- timestamp <= 9_223_372_036_854_775_807,
         {:ok, _nonce} <- decode32(nonce_text),
         {:ok, mac} <- decode32(mac_text) do
      %{key_id: kid, timestamp_text: ts_text, timestamp: timestamp, nonce: nonce_text, mac: mac}
    else
      _ -> nil
    end
  end

  defp ascii?(value), do: value |> :binary.bin_to_list() |> Enum.all?(&(&1 <= 127))

  defp valid_timestamp_text?(text) do
    byte_size(text) in 1..19 and Regex.match?(~r/\A[0-9]+\z/, text) and
      (byte_size(text) == 1 or not String.starts_with?(text, "0"))
  end

  defp decode32(text) do
    with true <- byte_size(text) == 43 and Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, text),
         {:ok, bytes} <- Base.url_decode64(text, padding: false),
         true <- byte_size(bytes) == 32 and Base.url_encode64(bytes, padding: false) == text do
      {:ok, bytes}
    else
      _ -> :error
    end
  end

  # Canonicalization

  @doc false
  @spec frame(String.t()) :: String.t()
  def frame(value), do: "#{byte_size(value)}:#{value}\n"

  @doc false
  @spec canonical_path(String.t() | nil) :: String.t() | nil
  def canonical_path(raw_target) when is_binary(raw_target) and raw_target != "" do
    with "/" <> _ <- raw_target,
         false <-
           raw_target |> :binary.bin_to_list() |> Enum.any?(&(&1 <= 32 or &1 >= 127 or &1 == ?#)),
         [path | _] <- String.split(raw_target, "?", parts: 2),
         {:ok, upcased} <- upcase_escapes(path, []) do
      upcased
    else
      _ -> nil
    end
  end

  def canonical_path(_), do: nil

  defp upcase_escapes(<<?%, a, b, rest::binary>>, acc) do
    if hex?(a) and hex?(b),
      do:
        upcase_escapes(rest, [
          <<?%, String.upcase(<<a>>)::binary, String.upcase(<<b>>)::binary>> | acc
        ]),
      else: :error
  end

  defp upcase_escapes(<<?%, _::binary>>, _acc), do: :error
  defp upcase_escapes(<<c, rest::binary>>, acc), do: upcase_escapes(rest, [<<c>> | acc])
  defp upcase_escapes(<<>>, acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

  defp hex?(c), do: c in ?0..?9 or c in ?a..?f or c in ?A..?F

  defp canonicalize(observed, configuration, envelope) do
    with true <- token?(observed.method) and observed.method == String.upcase(observed.method),
         path when is_binary(path) <- canonical_path(observed.raw_target) do
      names =
        observed.headers
        |> Map.delete(@header)
        |> Map.keys()
        |> Enum.sort()

      if length(names) > 64,
        do: nil,
        else: build(observed, configuration, envelope, {path, names})
    else
      _ -> nil
    end
  end

  defp build(observed, configuration, envelope, {path, names}) do
    prefix =
      [
        configuration.audience,
        envelope.key_id,
        envelope.timestamp_text,
        envelope.nonce,
        observed.method,
        path,
        Integer.to_string(length(names))
      ]
      |> Enum.map(&frame/1)

    result =
      Enum.reduce_while(names, {:ok, [], %{}}, fn name, {:ok, frames, headers} ->
        value = observed.headers[name] |> String.trim(" ") |> trim_tabs()

        with true <- token?(name), true <- printable?(value) do
          {:cont, {:ok, [frame(value), frame(name) | frames], Map.put(headers, name, value)}}
        else
          _ -> {:halt, :error}
        end
      end)

    with {:ok, frames, headers} <- result,
         true <-
           Enum.all?(
             [@principal_header, @id_header, @name_header],
             &(Map.get(headers, &1, "") != "")
           ) do
      canonical = IO.iodata_to_binary([@canonical_prefix, prefix, Enum.reverse(frames)])

      if byte_size(canonical) > @max_canonical,
        do: nil,
        else: %{
          bytes: canonical,
          headers: headers,
          method: observed.method,
          raw_path: observed.raw_target |> String.split("?", parts: 2) |> hd()
        }
    else
      _ -> nil
    end
  end

  # Strip only outer HTTP optional whitespace (SP and HTAB).
  defp trim_tabs(value),
    do: value |> String.trim_leading("\t") |> String.trim_trailing("\t") |> String.trim(" ")

  defp printable?(value),
    do: value |> :binary.bin_to_list() |> Enum.all?(&(&1 >= ?\s and &1 < 127))

  defp token?(value) do
    value != "" and
      value
      |> :binary.bin_to_list()
      |> Enum.all?(&(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 in ~c"!#$%&'*+-.^_`|~"))
  end

  # Verification

  @doc false
  @spec verify(map(), map(), map(), module(), integer()) :: {:ok, map(), map()} | :error
  def verify(request, envelope, configuration, app, now) do
    with true <- envelope.timestamp >= now - 60 and envelope.timestamp <= now + 30,
         {:ok, key} <- Map.fetch(configuration.keys, envelope.key_id),
         mac = :crypto.mac(:hmac, :sha256, key, request.bytes),
         true <- :crypto.hash_equals(mac, envelope.mac),
         {:ok, client} <-
           Forwarded.read_principal(request.headers[@principal_header], strict: true),
         subject when is_binary(subject) <-
           Forwarded.decode_header_value(request.headers[@id_header]),
         true <- String.trim(subject) != "" and client.user_id == subject,
         true <-
           ReplayCache.reserve_forwarded(
             app,
             {configuration.audience, envelope.key_id, envelope.nonce},
             envelope.timestamp + 60,
             now
           ) do
      {:ok, client, request.headers}
    else
      _ -> :error
    end
  end

  defp verify_and_build(request, envelope, configuration, context) do
    case verify(request, envelope, configuration, context.app, context.now) do
      :error ->
        {:failed, "forwarded-identity-rejected"}

      {:ok, client, headers} ->
        principal = Forwarded.to_principal(client, headers[@id_header])

        if OnBehalfOf.present?(&Map.has_key?(headers, &1)),
          do: with_actor(principal, request, context),
          else: {:authenticated, principal}
    end
  end

  # An actor or assertion header makes this an on-behalf forward: it is authenticated as one or not at all.
  defp with_actor(principal, request, %{app: app, config: config, now: now}) do
    headers = request.headers

    forward = %{
      principal: headers[@principal_header],
      principal_id: headers[@id_header],
      actor: headers[OnBehalfOf.actor_header()],
      assertion: headers[OnBehalfOf.assertion_header()],
      tenant: tenant_value(headers, config),
      method: request.method,
      path: request.raw_path
    }

    with {:ok, _actor_client} <- Forwarded.read_principal(forward.actor, strict: true),
         {:ok, actor, _valid_until} <-
           OnBehalfOf.attach(
             forward,
             principal,
             app,
             config,
             OnBehalfOf.signing_keys(config),
             now
           ) do
      {:authenticated, %{principal | actor: actor}}
    else
      _ -> {:failed, "forwarded-identity-invalid-actor"}
    end
  end

  defp tenant_value(headers, config) do
    case config[:tenant_header] do
      header when is_binary(header) and header != "" -> headers[String.downcase(header)]
      _ -> nil
    end
  end
end
