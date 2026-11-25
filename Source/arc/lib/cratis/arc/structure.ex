# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Structure do
  @moduledoc """
  The structure of an application: its modules, features, sub-features and slices, each with the
  commands and read models it holds. It is what `/.cratis/structure` answers, the same shape as Arc
  for .NET.

  A module, feature or slice is identified by a *path*: the names from the module down, joined with
  `/`. A feature is nested when its namespace has more than one segment between the module and the
  slice, so `Fleet.Quality.Scores.Rank` is the slice `Rank` of the sub-feature `Scores` of the
  feature `Quality` of the module `Fleet`: `Fleet/Quality/Scores/Rank`.

  Parts that belong to no module are in a module with an empty name.
  """

  alias Cratis.Arc.Descriptor

  @separator "/"

  @doc "The separator of the segments of a path."
  @spec separator() :: String.t()
  def separator, do: @separator

  @doc """
  The path segments of the slice a descriptor belongs to: the module, each feature it is nested in,
  then the slice. Empty segments are left out.
  """
  @spec segments(Descriptor.t(), integer()) :: [String.t()]
  def segments(descriptor, segments_to_skip) do
    {module, feature, slice} = Descriptor.slice_location(descriptor, segments_to_skip)
    location_segments(module, feature, slice)
  end

  @doc false
  @spec location_segments(String.t(), String.t(), String.t()) :: [String.t()]
  def location_segments(module, feature, slice),
    do: Enum.reject([module | String.split(feature, ".")] ++ [slice], &(&1 == ""))

  @doc """
  Whether a path is, or sits beneath, an ancestor path. Whole segments only: `"Fleet"` covers
  `"Fleet/Quality"` and not `"Fleets"`.
  """
  @spec within?([String.t()], String.t()) :: boolean()
  def within?(segments, ancestor) do
    prefix = String.split(ancestor, @separator, trim: true)

    prefix != [] and length(prefix) <= length(segments) and
      Enum.take(segments, length(prefix)) == prefix
  end

  @doc """
  Builds the structure of the commands and read models of an application, with `segments_to_skip`
  leading namespace segments left out of every location.
  """
  @spec build([Descriptor.t()], [Descriptor.t()], integer()) :: map()
  def build(commands, read_models, segments_to_skip) do
    parts =
      Enum.map(commands, &entry(&1, "Command", segments_to_skip)) ++
        Enum.map(read_models, &entry(&1, "ReadModel", segments_to_skip))

    modules =
      parts
      |> Enum.group_by(fn {module, _segments, _part} -> module end, fn {_module, segments, part} ->
        {segments, part}
      end)
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, members} -> module(name, members) end)

    %{"modules" => modules}
  end

  # The module, the features and slice below it, and the part.
  defp entry(descriptor, kind, segments_to_skip) do
    {module, feature, slice} = Descriptor.slice_location(descriptor, segments_to_skip)
    {module, location_segments("", feature, slice), part(descriptor, kind)}
  end

  defp part(descriptor, kind) do
    full_name = inspect(descriptor.module)

    %{
      "name" => full_name |> String.split(".") |> List.last(),
      "fullName" => full_name,
      "kind" => kind
    }
  end

  defp module(name, members) do
    node = node(name, members)
    %{"name" => name, "path" => name, "features" => node.features, "slices" => node.slices}
  end

  # Every entry is {remaining segments, part}. The last remaining segment is the slice, those before
  # it are features. An entry with no segment left is a slice named after the part.
  defp node(path, entries) do
    {here, deeper} = Enum.split_with(entries, fn {segments, _} -> length(segments) <= 1 end)

    slices =
      here
      |> Enum.group_by(fn
        {[], part} -> part["name"]
        {[slice], _part} -> slice
      end)
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, group} ->
        %{
          "name" => name,
          "path" => join(path, name),
          "parts" => group |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort_by(& &1["name"])
        }
      end)

    features =
      deeper
      |> Enum.group_by(fn {[feature | _], _} -> feature end, fn {[_ | rest], part} ->
        {rest, part}
      end)
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, group} ->
        child = node(join(path, name), group)

        %{
          "name" => name,
          "path" => join(path, name),
          "features" => child.features,
          "slices" => child.slices
        }
      end)

    %{features: features, slices: slices}
  end

  defp join("", name), do: name
  defp join(path, name), do: path <> @separator <> name
end
