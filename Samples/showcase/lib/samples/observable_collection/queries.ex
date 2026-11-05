# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.ObservableCollection.Queries do
  @moduledoc "Queries over the observable collection."

  use Arc.ReadModel, model: Samples.ObservableCollection.ObservableCollectionItem
  allow_anonymous()

  @doc "Observes the current collection: pushed when items are added or removed."
  @observe many: true, topics: ["observable-collection"]
  def all(_args, _ctx), do: {:ok, Samples.Store.get(:observable_collection)}
end
