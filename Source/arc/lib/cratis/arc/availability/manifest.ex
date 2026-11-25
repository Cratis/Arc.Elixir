# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Availability.Manifest do
  @moduledoc """
  The availability manifest file, format `cratis-availability-manifest` version 1: the audiences,
  blocks, conditions, gates, context values, parts and suspendable parts of an application in one
  format every Arc implementation reads and writes. The schema and the shared test vectors live in
  `Specifications/availability` of the Cratis/Arc repository.

  `build/1` writes the manifest of an application; `decode/1` reads one and checks its shape;
  `decide/3` decides a part of a manifest over a context, which is what the shared vectors run.
  """

  alias Cratis.Arc.Availability.{Engine, Paths}

  @format "cratis-availability-manifest"

  @doc "The manifest of an application, as a map ready to be encoded as JSON."
  @spec build(module()) :: map()
  def build(app) do
    state = Cratis.Arc.Application.state(app)
    availability = state.availability
    definition = availability.definition

    %{
      "format" => @format,
      "version" => 1,
      "origin" => "Arc for Elixir",
      "audiences" => definition.audiences,
      "blocks" => definition.blocks,
      "conditions" => conditions(availability),
      "contextValues" =>
        for(
          v <- definition.values,
          do: %{
            "name" => v.name,
            "scope" => "",
            "required" => v.required,
            "origin" => inspect(v.provider)
          }
        ),
      "scopes" => Enum.sort_by(definition.scopes, & &1["namespace"]),
      "parts" =>
        for p <- availability.list do
          %{
            "name" => p.name,
            "kind" => p.kind,
            "module" => p.module,
            "feature" => p.feature,
            "slice" => p.slice,
            "gates" => p.gates
          }
        end,
      "suspendable" => suspendable(availability.list)
    }
  end

  @doc "The manifest of an application, as JSON."
  @spec to_json(module()) :: String.t()
  def to_json(app), do: app |> build() |> Jason.encode!(pretty: true)

  defp conditions(availability) do
    availability.conditions
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(fn name ->
      module = Map.fetch!(availability.conditions, name)

      description =
        if function_exported?(module, :description, 0), do: module.description(), else: ""

      %{"name" => name, "description" => description}
    end)
  end

  defp suspendable(parts) do
    locations =
      for p <- parts, reduce: MapSet.new() do
        acc ->
          [p.module, "#{p.module}/#{p.feature}", "#{p.module}/#{p.feature}/#{p.slice}"]
          |> Enum.zip([:module, :feature, :slice])
          |> Enum.reduce(acc, fn {path, kind}, acc ->
            MapSet.put(acc, {kind, trim(path), last(path)})
          end)
      end

    locations =
      for {kind, path, name} <- locations,
          path != "",
          do: %{"kind" => Atom.to_string(kind), "path" => path, "name" => name}

    named = for p <- parts, do: %{"kind" => "part", "path" => p.path, "name" => p.name}
    Enum.sort_by(locations ++ named, &{&1["path"], &1["kind"]})
  end

  defp trim(path), do: path |> String.split("/") |> Enum.reject(&(&1 == "")) |> Enum.join("/")
  defp last(path), do: path |> trim() |> String.split("/") |> List.last() || ""

  @doc "Decodes and checks a manifest document given as JSON."
  @spec decode(String.t() | map()) :: {:ok, map()} | {:error, String.t()}
  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, document} -> decode(document)
      {:error, _} -> {:error, "The manifest is not JSON."}
    end
  end

  def decode(%{"format" => @format, "version" => 1} = document) do
    required = ~w(origin audiences blocks conditions contextValues scopes parts suspendable)

    case Enum.find(required, &(not is_list(Map.get(document, &1)) and &1 != "origin")) do
      nil -> {:ok, document}
      key -> {:error, "The manifest has no #{key}."}
    end
  end

  def decode(_other), do: {:error, "This is not a version 1 availability manifest."}

  @doc """
  Decides a part of a manifest document over a context:
  `%{tenant:, user:, audiences: [], suspended: [], values: %{}, arguments: %{}}` (all optional).

  Returns `%{available: boolean, reason: nil | "NotAvailable" | "Suspended"}`. A part the manifest
  does not list is available.
  """
  @spec decide(map(), String.t(), map()) :: %{available: boolean(), reason: String.t() | nil}
  def decide(document, name, context) do
    case Enum.find(document["parts"], &(&1["name"] == name)) do
      nil ->
        %{available: true, reason: nil}

      entry ->
        part = %{
          name: entry["name"],
          path: Paths.for_part(entry["module"], entry["feature"], entry["slice"], entry["name"]),
          gates: entry["gates"]
        }

        held = Map.get(context, :audiences, [])

        ambient =
          context
          |> Map.get(:values, %{})
          |> Map.put("tenant", Map.get(context, :tenant))
          |> Map.put("identity", %{"user" => Map.get(context, :user), "isSystem" => false})
          |> then(fn ambient ->
            case Map.fetch(context, :arguments) do
              {:ok, arguments} -> Map.put(ambient, "arguments", arguments)
              :error -> ambient
            end
          end)

        env = %{
          ambient: ambient,
          audiences: fn -> {:ok, held} end,
          blocks: Map.new(document["blocks"], &{&1["name"], &1["gate"]}),
          suspended: Map.get(context, :suspended, [])
        }

        case Engine.decide(part, env) do
          {:ok, :available} -> %{available: true, reason: nil}
          {:ok, :suspended} -> %{available: false, reason: "Suspended"}
          {:ok, {_, _}} -> %{available: false, reason: "NotAvailable"}
          {:error, reason} -> raise "The decision failed: #{inspect(reason)}"
        end
    end
  end
end
