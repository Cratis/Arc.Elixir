# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Identity.Forwarded do
  @moduledoc false

  # Shared pieces of forwarded identity: RFC 8187 header values, the client principal payload and
  # how it becomes an `Arc.Principal`. These follow the Arc on .NET rules exactly.

  alias Arc.Principal

  @role_claim "http://schemas.microsoft.com/ws/2008/06/identity/claims/role"
  @name_identifier_claim "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"
  @identity_provider_claim "urn:cratis:arc:identity:provider"

  def identity_provider_claim, do: @identity_provider_claim
  def name_identifier_claim, do: @name_identifier_claim
  def role_claim, do: @role_claim

  @doc """
  Decodes an RFC 8187 `UTF-8''` extended value. A value without the prefix is returned as is.
  Returns `nil` for malformed percent escapes, non-ASCII input or invalid UTF-8.
  """
  @spec decode_header_value(String.t()) :: String.t() | nil
  def decode_header_value(value) do
    case value do
      <<prefix::binary-size(7), encoded::binary>> ->
        if String.downcase(prefix) == "utf-8''", do: percent_decode(encoded), else: value

      _ ->
        value
    end
  end

  defp percent_decode(encoded) do
    with {:ok, octets} <- octets(encoded, []),
         true <- String.valid?(octets),
         do: octets,
         else: (_ -> nil)
  end

  defp octets(<<>>, acc), do: {:ok, acc |> Enum.reverse() |> :erlang.list_to_binary()}

  defp octets(<<?%, a, b, rest::binary>>, acc) do
    case Integer.parse(<<a, b>>, 16) do
      {value, ""} -> octets(rest, [value | acc])
      _ -> :error
    end
  end

  defp octets(<<?%, _::binary>>, _acc), do: :error
  defp octets(<<c, rest::binary>>, acc) when c < 0x80, do: octets(rest, [c | acc])
  defp octets(_, _acc), do: :error

  @doc """
  Reads a base64 client principal.

  With `strict: true` the principal must have a non-blank `userId`, a `userDetails`, claims with a
  type and a value, and roles. Returns `{:ok, client}` or `:error`.
  """
  @spec read_principal(String.t() | nil, keyword()) :: {:ok, map()} | :error
  def read_principal(header, opts \\ [])
  def read_principal(nil, _opts), do: :error

  def read_principal(header, opts) do
    with {:ok, bytes} <- Base.decode64(header),
         true <- String.valid?(bytes),
         {:ok, %{} = json} <- Jason.decode(bytes) do
      normalize(json, Keyword.get(opts, :strict, false))
    else
      _ -> :error
    end
  end

  defp normalize(json, strict?) do
    json = Map.new(json, fn {k, v} -> {String.downcase(k), v} end)

    client = %{
      identity_provider: json["identityprovider"],
      user_id: json["userid"],
      user_details: json["userdetails"],
      roles: json["userroles"],
      claims: json["claims"]
    }

    if strict?, do: validate(client), else: {:ok, loosen(client)}
  end

  defp validate(%{user_id: id, user_details: details, roles: roles, claims: claims} = client) do
    with true <- is_binary(id) and String.trim(id) != "",
         true <- is_binary(details),
         true <- is_list(roles) and Enum.all?(roles, &is_binary/1),
         true <- is_list(claims),
         {:ok, pairs} <- claim_pairs(claims) do
      {:ok, %{client | claims: pairs}}
    else
      _ -> :error
    end
  end

  defp loosen(client) do
    pairs =
      case client.claims do
        list when is_list(list) -> with {:ok, p} <- claim_pairs(list), do: p, else: (_ -> [])
        _ -> []
      end

    %{
      client
      | claims: pairs,
        roles: if(is_list(client.roles), do: Enum.filter(client.roles, &is_binary/1), else: []),
        user_id: client.user_id || "",
        user_details: client.user_details || ""
    }
  end

  defp claim_pairs(claims) do
    Enum.reduce_while(claims, {:ok, []}, fn
      %{} = claim, {:ok, acc} ->
        claim = Map.new(claim, fn {k, v} -> {String.downcase(k), v} end)

        case {claim["typ"], claim["val"]} do
          {type, value} when is_binary(type) and type != "" and is_binary(value) ->
            {:cont, {:ok, [{type, value} | acc]}}

          _ ->
            {:halt, :error}
        end

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      :error -> :error
    end
  end

  @doc """
  Builds the principal for a client principal and the identity id header, the way Arc on .NET
  builds its claims: the id is the decoded header, the name is `userDetails`, the roles are
  `userRoles` plus claims of the role claim type, and `sub` and the name identifier are set from the
  header (replacing any in the payload).
  """
  @spec to_principal(map(), String.t()) :: Principal.t()
  def to_principal(client, identity_id_header) do
    id = decode_header_value(identity_id_header) || identity_id_header

    claims =
      client.claims
      |> Enum.reject(fn {type, _} ->
        type in [@name_identifier_claim, "sub"] or
          String.downcase(type) == @identity_provider_claim
      end)

    claims = claims ++ [{"sub", id}, {@name_identifier_claim, id}]

    claims =
      if is_binary(client.identity_provider) and String.trim(client.identity_provider) != "",
        do: claims ++ [{@identity_provider_claim, client.identity_provider}],
        else: claims

    roles = client.roles ++ for {@role_claim, value} <- claims, do: value

    %Principal{
      id: id,
      name: client.user_details,
      authenticated?: true,
      roles: roles,
      claims: group(claims)
    }
  end

  defp group(pairs) do
    pairs
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn
      {type, [value]} -> {type, value}
      {type, values} -> {type, values}
    end)
  end
end
