# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.MongoWatcher.AddWatcherItem do
  @moduledoc "Adds an item to the tenant's watcher collection."

  use Arc.Command
  allow_anonymous()

  schema do
    field :name, :string, required: true, max_length: 100
  end

  alias Samples.MongoWatcher.WatcherItem

  def handle(%__MODULE__{name: name}, ctx) do
    item = %WatcherItem{id: Arc.new_id(), name: name, created_at: DateTime.utc_now()}
    {:ok, _} = Arc.MongoDB.insert({ctx, WatcherItem}, item)
    {:ok, nil}
  end
end
