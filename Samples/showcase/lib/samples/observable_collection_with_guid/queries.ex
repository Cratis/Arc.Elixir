# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.ObservableCollectionWithGuid.Queries do
  @moduledoc "Queries over the observable collection with GUID identities."

  use Arc.ReadModel,
    model: Samples.ObservableCollectionWithGuid.ObservableCollectionWithGuidItem,
    types: [id: :uuid]

  allow_anonymous()

  @doc "Observes the current collection."
  @observe many: true, topics: ["observable-collection-with-guid"]
  def all(_args, _ctx), do: {:ok, Samples.Store.get(:observable_collection_with_guid)}
end
