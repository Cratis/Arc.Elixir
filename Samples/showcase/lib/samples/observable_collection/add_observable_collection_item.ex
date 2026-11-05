# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.ObservableCollection.AddObservableCollectionItem do
  @moduledoc "Appends an item to the collection."

  use Arc.Command
  allow_anonymous()

  schema do
    field :id, :integer, required: true
    field :label, :string, required: true
  end

  def handle(%__MODULE__{id: id, label: label}, _ctx) do
    item = %Samples.ObservableCollection.ObservableCollectionItem{id: id, label: label}
    Samples.Store.update(:observable_collection, "observable-collection", &(&1 ++ [item]))
    {:ok, nil}
  end
end
