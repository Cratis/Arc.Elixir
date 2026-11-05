# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.ConnectionResolver.Template do
  @moduledoc """
  Places tenants with a naming rule instead of an endpoint.

      connection_resolution: [
        connection: {:template, database: "tenant-{tenant}"}
      ]

  Options are `:connection_string` and `:database`. A template may use any scope value in braces
  (`{tenant}`), as well as `{purpose}` and `{storage}`. A placeholder with no value fails instead
  of connecting somewhere unintended.
  """

  alias Arc.MongoDB.ResolvedConnection

  @doc "Resolves a request with the template options."
  @spec resolve(Arc.MongoDB.ConnectionResolver.request(), keyword()) ::
          {:ok, ResolvedConnection.t()} | {:error, term()}
  def resolve(request, options) do
    values =
      Map.merge(request.scope, %{
        "purpose" => request.purpose |> Atom.to_string() |> String.capitalize(),
        "storage" => request.storage
      })

    with {:ok, connection_string} <- render(options[:connection_string], values),
         {:ok, database} <- render(options[:database], values) do
      {:ok, %ResolvedConnection{connection_string: connection_string, database: database}}
    end
  end

  defp render(nil, _values), do: {:ok, nil}

  defp render(template, values) do
    ~r/\{([A-Za-z0-9_]+)\}/
    |> Regex.scan(template)
    |> Enum.reduce_while({:ok, template}, fn [placeholder, name], {:ok, text} ->
      case Map.get(values, name) do
        value when is_binary(value) and value != "" ->
          {:cont, {:ok, String.replace(text, placeholder, value)}}

        _ ->
          {:halt, {:error, "The template placeholder #{placeholder} has no value."}}
      end
    end)
  end
end
