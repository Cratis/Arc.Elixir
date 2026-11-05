# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.MongoWatcher.WatcherItem do
  @moduledoc """
  An item stored in the `watcherItems` collection of the tenant's database.

  A document is a struct. `types:` says how the fields are stored, where the struct's defaults do
  not: the id is a UUID (BSON binary, subtype 4) and `created_at` a date time.
  """

  use Arc.MongoDB.Document, types: [id: :uuid, created_at: :datetime]

  defstruct id: "", name: "", created_at: ~U[1970-01-01 00:00:00Z]
end
