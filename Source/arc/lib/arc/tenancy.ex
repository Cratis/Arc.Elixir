# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Tenancy do
  @moduledoc """
  Resolves which tenant a request is for.

  Tenancy has three separate decisions. **Selection** (this module) resolves the tenant id.
  **Membership authorization** checks that the caller may use it, and is yours to enforce.
  **Storage isolation** decides where data lives: `ArcMongo` names the database after the tenant,
  and Arc maps the tenant to the Chronicle event store namespace. None of these replaces the
  others, and a resolver only selects: a caller-controlled header, query string or host is not
  membership evidence.

  The resolved tenant is `ctx.tenant`: a string, or `nil` when nothing selected one. `nil` and
  `"Default"` are both the *default* tenant (see `default?/1`) and select the default database
  and the default Chronicle namespace; they are not rejected.

  ## Configuration

  The `:tenancy` option of the Arc application selects one resolver:

      config :my_app, MyApp.Arc,
        tenancy: [resolver: :header, header: "x-cratis-tenant-id"]

  | Resolver | Options | Default |
  | --- | --- | --- |
  | `:header` | `:header` | `"x-cratis-tenant-id"` (or the `:tenant_header` option) |
  | `:query` | `:query_parameter` | `"tenantId"` |
  | `:claim` | `:claim_type` | `"tenant_id"` |
  | `:subdomain` | `:base_domain` (required), `:header` | falls back to the header |
  | `:fixed` | `:tenant_id` | `"development"` |
  | `:development` | `:tenant_id` | `"development"`, same behavior as `:fixed` |

  `resolver` may also be a module implementing this behaviour, for example one that consults a
  session. The `:claim` resolver reads the principal, so authentication must have run; the
  `:subdomain` resolver's fallback header is client-supplied, so strip it at your ingress.

  A subdomain resolves a tenant only when it is exactly one DNS label in front of `:base_domain`:
  `acme.myapp.com` is `acme`, while `myapp.com`, `acme.staging.myapp.com`, IP literals and
  unrelated hosts such as `evil-myapp.com` fall back to the header. The base domain is required
  and must be a registrable domain you own (at least two letter-digit-hyphen labels, never an
  address literal); the application refuses to start otherwise, because without it every request
  would silently take its tenant from the client-supplied header.

  Hosts are matched after Unicode compatibility mapping (NFKC), the ideographic and fullwidth
  full stops count as label separators and zero-width characters are ignored. Internationalized
  labels are not converted to punycode: write them as `xn--` labels in configuration and traffic.
  """

  alias Arc.Principal

  @default_header "x-cratis-tenant-id"
  @default_tenant "development"
  @label ~r/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/

  @doc """
  Selects the tenant id for a request.

  `principal` is the authenticated caller (or anonymous) and `conn` the request.
  """
  @callback resolve(Plug.Conn.t(), Principal.t(), keyword()) :: String.t() | nil

  @doc "Whether a tenant is the default: not set, empty, or `\"Default\"`."
  @spec default?(String.t() | nil) :: boolean()
  def default?(nil), do: true
  def default?(""), do: true

  def default?(tenant) when is_binary(tenant),
    do: String.downcase(tenant) in ["default", "[notset]"]

  @doc """
  The Chronicle options that scope a call to the tenant: `namespace: tenant` for a named tenant,
  nothing for the default one. An explicit `:namespace` in `chronicle` wins.
  """
  @spec chronicle_options(keyword(), String.t() | nil) :: keyword()
  def chronicle_options(chronicle, tenant) do
    if default?(tenant) or Keyword.has_key?(chronicle, :namespace),
      do: chronicle,
      else: Keyword.put(chronicle, :namespace, tenant)
  end

  @doc """
  Resolves the tenant of a request with the configured resolver.
  """
  @spec resolve(Plug.Conn.t(), Principal.t(), keyword()) :: String.t() | nil
  def resolve(conn, principal, config) do
    options = options(config)
    resolve_with(options[:resolver], conn, principal, options)
  end

  @doc """
  The normalized tenancy options of an application configuration.

  Raises `ArgumentError` when the configuration cannot select a tenant safely, for example a
  subdomain resolver without a usable base domain.
  """
  @spec options(keyword()) :: keyword()
  def options(config) do
    raw = Keyword.get(config, :tenancy, [])
    header = Keyword.get(raw, :header) || Keyword.get(config, :tenant_header) || @default_header

    [
      resolver: Keyword.get(raw, :resolver, :header),
      header: String.downcase(header),
      query_parameter: Keyword.get(raw, :query_parameter, "tenantId"),
      claim_type: Keyword.get(raw, :claim_type, "tenant_id"),
      base_domain: Keyword.get(raw, :base_domain),
      tenant_id: Keyword.get(raw, :tenant_id, @default_tenant)
    ]
  end

  @doc """
  Validates the tenancy configuration, raising `ArgumentError` when it is unusable.
  """
  @spec validate!(keyword()) :: :ok
  def validate!(config) do
    options = options(config)

    if options[:resolver] == :subdomain do
      base = normalize_host(options[:base_domain] || "")

      unless valid_base_domain?(base) do
        raise ArgumentError,
              "The subdomain tenancy resolver needs :base_domain to be a registrable domain " <>
                "such as \"myapp.com\", but it is #{inspect(options[:base_domain])}. " <>
                "Without it every request would take its tenant from the client-supplied header."
      end
    end

    :ok
  end

  defp resolve_with(:header, conn, _principal, options), do: header(conn, options[:header])

  defp resolve_with(:query, conn, _principal, options) do
    conn = Plug.Conn.fetch_query_params(conn)
    blank_to_nil(conn.query_params[options[:query_parameter]])
  end

  defp resolve_with(:claim, _conn, principal, options) do
    case Map.get(principal.claims, options[:claim_type]) do
      [value | _] -> blank_to_nil(value)
      value when is_binary(value) -> blank_to_nil(value)
      _ -> nil
    end
  end

  defp resolve_with(:subdomain, conn, _principal, options) do
    base = normalize_host(options[:base_domain] || "")

    case subdomain(conn.host, base) do
      nil -> header(conn, options[:header])
      label -> label
    end
  end

  defp resolve_with(kind, _conn, _principal, options) when kind in [:fixed, :development],
    do: options[:tenant_id]

  defp resolve_with(module, conn, principal, options) when is_atom(module),
    do: module.resolve(conn, principal, options)

  defp header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] -> blank_to_nil(value)
      [] -> nil
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  # The label in front of the base domain, when the host is exactly one label deeper.
  defp subdomain(host, base) do
    host = normalize_host(host)

    with true <- valid_base_domain?(base),
         true <- String.ends_with?(host, "." <> base),
         label = String.replace_suffix(host, "." <> base, ""),
         true <- Regex.match?(@label, label) do
      label
    else
      _ -> nil
    end
  end

  defp valid_base_domain?(base) do
    labels = String.split(base, ".")

    length(labels) >= 2 and Enum.all?(labels, &Regex.match?(@label, &1)) and
      not Enum.all?(labels, &Regex.match?(~r/\A[0-9]+\z/, &1))
  end

  @separators ["\u3002", "\uFF0E", "\uFF61"]
  @ignorable ["\u200B", "\u00AD", "\uFEFF", "\u2060", "\u200C", "\u200D"]

  defp normalize_host(host) do
    host
    |> String.normalize(:nfkc)
    |> String.replace(@separators, ".")
    |> String.replace(@ignorable, "")
    |> String.downcase()
    |> strip_port()
    |> String.trim_trailing(".")
  end

  # `[::1]:8080` and `host:8080`; a bare IPv6 literal is left alone and never matches a domain.
  defp strip_port("[" <> _ = host), do: host

  defp strip_port(host) do
    case String.split(host, ":") do
      [name, port] -> if Regex.match?(~r/\A[0-9]*\z/, port), do: name, else: host
      _ -> host
    end
  end
end
