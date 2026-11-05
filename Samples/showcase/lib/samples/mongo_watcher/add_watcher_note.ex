# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.MongoWatcher.AddWatcherNote do
  @moduledoc "Adds a note to the tenant's notes collection."

  use Arc.Command
  allow_anonymous()

  schema do
    field :text, :string, required: true, max_length: 500
  end

  alias Samples.MongoWatcher.WatcherNote

  def handle(%__MODULE__{text: text}, ctx) do
    note = %WatcherNote{id: Arc.new_id(), text: text, created_at: DateTime.utc_now()}
    {:ok, _} = Arc.MongoDB.insert({ctx, WatcherNote}, note)
    {:ok, nil}
  end
end
