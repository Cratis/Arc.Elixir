# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.MongoWatcher.WatcherNote do
  @moduledoc "A note stored in the secondary collection of the watcher demo."

  use Arc.MongoDB.Document, types: [id: :uuid, created_at: :datetime]

  defstruct id: "", text: "", created_at: ~U[1970-01-01 00:00:00Z]
end
