# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.ConnectionResolver.Http do
  @moduledoc """
  Asks your platform where to connect, over HTTP.

      connection_resolution: [
        identity: {:http, endpoint: "https://platform.example/connections",
                          headers: [{"x-api-key", System.get_env("PLATFORM_KEY")}]}
      ]

  The endpoint receives `POST` with `{"storage": "MongoDB", "purpose": "Runtime", "scope":
  {"tenant": "acme"}}` and answers `200` with a JSON object of the parts it decides
  (`connectionString`, `database`, `identity`, `expiresAt`), `204` to keep the configured
  connection, or an error status, which fails the connection that needed it. The contract is the
  same for every storage, so one endpoint can serve Arc on .NET and Arc for Elixir.

  Options: `:endpoint` (required), `:headers` and `:timeout` in milliseconds (default `10_000`).
  The endpoint is called with the headers given; an OAuth bearer token is yours to supply, for
  example by a module resolver that wraps this one.
  """

  alias Arc.MongoDB.ResolvedConnection

  @doc "Calls the endpoint for a request."
  @spec resolve(Arc.MongoDB.ConnectionResolver.request(), keyword()) ::
          {:ok, ResolvedConnection.t()} | :unchanged | {:error, term()}
  def resolve(request, options) do
    endpoint = Keyword.fetch!(options, :endpoint)
    timeout = Keyword.get(options, :timeout, 10_000)

    body =
      Jason.encode!(%{
        "storage" => request.storage,
        "purpose" => request.purpose |> Atom.to_string() |> String.capitalize(),
        "scope" => request.scope
      })

    headers =
      for {name, value} <- Keyword.get(options, :headers, []),
          do: {to_charlist(name), to_charlist(value)}

    http_options = [timeout: timeout, autoredirect: true] ++ ssl_options(endpoint)

    case :httpc.request(
           :post,
           {to_charlist(endpoint), headers, ~c"application/json", body},
           http_options,
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _headers, response}} ->
        parse(response)

      {:ok, {{_, 204, _}, _headers, _response}} ->
        :unchanged

      {:ok, {{_, status, _}, _headers, _response}} ->
        {:error, "The resolver endpoint answered #{status}."}

      {:error, reason} ->
        {:error, "The resolver endpoint could not be called: #{inspect(reason)}"}
    end
  end

  defp ssl_options("https://" <> _) do
    [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]
  end

  defp ssl_options(_), do: []

  defp parse(response) do
    case Jason.decode(response) do
      {:ok, %{} = body} ->
        body = Map.new(body, fn {key, value} -> {String.downcase(key), value} end)

        {:ok,
         %ResolvedConnection{
           connection_string: body["connectionstring"],
           database: body["database"],
           schema: body["schema"],
           identity: identity(body["identity"]),
           expires_at: expires_at(body["expiresat"])
         }}

      _ ->
        {:error, "The resolver endpoint did not answer a JSON object."}
    end
  end

  defp identity(%{} = identity) do
    identity = Map.new(identity, fn {key, value} -> {String.downcase(key), value} end)

    %{
      user_name: identity["username"],
      password: identity["password"],
      access_token: identity["accesstoken"]
    }
  end

  defp identity(_), do: nil

  defp expires_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp expires_at(_), do: nil
end
