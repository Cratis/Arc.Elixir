# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.MongoWatcher.Notes.Queries do
  @moduledoc "Queries over the watcher notes."

  use Arc.ReadModel,
    model: Samples.MongoWatcher.WatcherNote,
    types: [id: :uuid, created_at: :datetime]

  allow_anonymous()

  alias Samples.MongoWatcher.{WatcherItem, WatcherNote}

  @doc "Observes all notes. Re-runs when the notes or the items change."
  @observe many: true,
           watch: [Arc.MongoDB.watch(WatcherNote), Arc.MongoDB.watch(WatcherItem)]
  def watch_all(_args, ctx),
    do: {:ok, Arc.MongoDB.all({ctx, WatcherNote}, sort: [created_at: :asc])}

  @doc "Observes all notes, re-running only when a note changes."
  @observe many: true, watch: [Arc.MongoDB.watch(WatcherNote)]
  def observe_all(_args, ctx),
    do: {:ok, Arc.MongoDB.all({ctx, WatcherNote}, sort: [created_at: :asc])}
end
