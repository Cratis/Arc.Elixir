# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.MongoWatcher.Items.Queries do
  @moduledoc "Queries over the watcher items."

  use Arc.ReadModel,
    model: Samples.MongoWatcher.WatcherItem,
    types: [id: :uuid, created_at: :datetime]

  allow_anonymous()

  alias Samples.MongoWatcher.{WatcherItem, WatcherNote}

  @doc """
  Observes all items. Re-runs when the items **or the notes** change: both collections are watched
  through the one change stream of the tenant's database.
  """
  @observe many: true,
           watch: [Arc.MongoDB.watch(WatcherItem), Arc.MongoDB.watch(WatcherNote)]
  def watch_all(_args, ctx),
    do: {:ok, Arc.MongoDB.all({ctx, WatcherItem}, sort: [created_at: :asc])}

  @doc "Observes all items, re-running only when an item changes."
  @observe many: true, watch: [Arc.MongoDB.watch(WatcherItem)]
  def observe_all(_args, ctx),
    do: {:ok, Arc.MongoDB.all({ctx, WatcherItem}, sort: [created_at: :asc])}

  @doc "The items as a page: paging and sorting happen in MongoDB."
  @query many: true
  def paged(_args, ctx), do: {:ok, Arc.MongoDB.page({ctx, WatcherItem}, %{})}
end
