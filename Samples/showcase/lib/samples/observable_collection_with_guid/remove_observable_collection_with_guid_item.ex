# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.ObservableCollectionWithGuid.RemoveObservableCollectionWithGuidItem do
  @moduledoc "Removes an item from the collection."

  use Arc.Command
  allow_anonymous()

  schema do
    field :id, :uuid, required: true
  end

  def handle(%__MODULE__{id: id}, _ctx) do
    Samples.Store.update(
      :observable_collection_with_guid,
      "observable-collection-with-guid",
      fn items -> Enum.reject(items, &(&1.id == id)) end
    )

    {:ok, nil}
  end
end
