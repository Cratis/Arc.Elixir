# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.QueryShowcase.Queries do
  @moduledoc """
  The four kinds of query: observable and regular, each returning one item or a collection.
  """

  use Arc.ReadModel, model: Samples.QueryShowcase.ShowcaseItem, types: [updated_at: :datetime]
  allow_anonymous()

  alias Samples.{QueryShowcase.ShowcaseItem, Store}

  @doc "Observable, one item: streams the latest showcase item."
  @observe many: false, topics: ["showcase"]
  def latest(_args, _ctx) do
    tick = Store.get(:showcase)
    {:ok, %ShowcaseItem{id: max(tick, 1), name: label(tick), updated_at: DateTime.utc_now()}}
  end

  @doc "Observable, a collection: streams the full list. Shared by subscribers through the query cache."
  @observe many: true, topics: ["showcase"]
  def all(_args, _ctx), do: {:ok, items(Store.get(:showcase))}

  @doc "Regular, one item by identifier."
  @query params: [id: :integer], many: false
  def by_id(%{id: id}, _ctx),
    do: {:ok, %ShowcaseItem{id: id, name: "Item ##{id}", updated_at: DateTime.utc_now()}}

  @doc "Regular, a fixed collection."
  @query many: true
  def get_all(_args, _ctx) do
    {:ok,
     for id <- 1..5 do
       %ShowcaseItem{id: id, name: "Static Item ##{id}", updated_at: DateTime.utc_now()}
     end}
  end

  defp label(0), do: "Initial"
  defp label(tick), do: "Update ##{tick}"

  defp items(tick) do
    suffix = if tick == 0, do: "", else: " (v#{tick})"
    names = ["Alpha", "Beta", "Gamma"] ++ if(tick == 0, do: [], else: ["Delta"])

    for {name, index} <- Enum.with_index(names, 1) do
      %ShowcaseItem{id: index, name: name <> suffix, updated_at: DateTime.utc_now()}
    end
  end
end
