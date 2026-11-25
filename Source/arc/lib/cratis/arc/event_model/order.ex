# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.EventModel.Order do
  @moduledoc false

  # Puts the slices of an event model in the order they are read: a fact is drawn before whatever
  # uses it. A view or an automation depends on the slices that own the events it consumes, so it
  # comes after them; features and modules follow the same order (a feature is as late as its latest slice), and a feature's own slices come
  # before its sub-features. Where nothing decides, state changes come before views and automations,
  # then names. A cycle is broken where it is found, so the order is always total and stable.

  @doc "The slices in reading order, depth first: a feature's slices, then its sub-features."
  @spec sort([map()]) :: [map()]
  def sort(slices) do
    ranks = ranks(slices)

    slices
    |> Enum.group_by(& &1.module)
    |> Enum.sort_by(fn {module, group} -> {latest(group, ranks), module} end)
    |> Enum.flat_map(fn {_module, group} -> node(group, 0, ranks) end)
  end

  @doc "The segments of a slice's feature path."
  @spec path(map()) :: [String.t()]
  def path(%{feature: ""}), do: []
  def path(%{feature: feature}), do: String.split(feature, ".")

  defp node(slices, depth, ranks) do
    {own, deeper} = Enum.split_with(slices, &(length(path(&1)) == depth))

    children =
      deeper
      |> Enum.group_by(&Enum.at(path(&1), depth))
      |> Enum.sort_by(fn {name, group} -> {latest(group, ranks), name} end)
      |> Enum.flat_map(fn {_name, group} -> node(group, depth + 1, ranks) end)

    Enum.sort_by(own, &{Map.fetch!(ranks, &1.key), &1.type, &1.name}) ++ children
  end

  # A feature is as late as its latest slice: it cannot be drawn before everything inside it can.
  defp latest(group, ranks), do: group |> Enum.map(&Map.fetch!(ranks, &1.key)) |> Enum.max()

  # The longest chain of slices a slice depends on.
  defp ranks(slices) do
    by_key = Map.new(slices, &{&1.key, &1})

    Enum.reduce(slices, %{}, fn slice, acc ->
      {_rank, acc} = rank(slice.key, by_key, acc, MapSet.new())
      acc
    end)
  end

  defp rank(key, by_key, acc, visiting) do
    case acc do
      %{^key => rank} ->
        {rank, acc}

      _ ->
        slice = Map.fetch!(by_key, key)

        {deps, acc} =
          slice
          |> dependencies()
          |> Enum.filter(&(Map.has_key?(by_key, &1) and not MapSet.member?(visiting, &1)))
          |> Enum.map_reduce(acc, fn dep, acc ->
            rank(dep, by_key, acc, MapSet.put(visiting, key))
          end)

        rank = if deps == [], do: 0, else: Enum.max(deps) + 1
        {rank, Map.put(acc, key, rank)}
    end
  end

  @doc false
  # The slices whose events a view or an automation consumes.
  def dependencies(%{type: type} = slice) when type in [1, 2] do
    slice.external
    |> Enum.map(& &1.owner)
    |> Enum.reject(&(is_nil(&1) or &1 == slice.key))
    |> Enum.uniq()
  end

  def dependencies(_slice), do: []
end
