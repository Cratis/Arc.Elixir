# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Store do
  @moduledoc """
  The in-memory state of the showcase: what the .NET samples keep in static `BehaviorSubject`s.

  A write goes through `update/3`, which tells the observable queries subscribed to the topic, so
  every connected client sees it.
  """

  use Agent

  alias Samples.Arc, as: App

  @initial %{
    observable_collection: [
      %Samples.ObservableCollection.ObservableCollectionItem{id: 1, label: "One"},
      %Samples.ObservableCollection.ObservableCollectionItem{id: 2, label: "Two"}
    ],
    observable_collection_with_guid: [
      %Samples.ObservableCollectionWithGuid.ObservableCollectionWithGuidItem{
        id: "11111111-1111-1111-1111-111111111111",
        label: "One"
      },
      %Samples.ObservableCollectionWithGuid.ObservableCollectionWithGuidItem{
        id: "22222222-2222-2222-2222-222222222222",
        label: "Two"
      }
    ],
    change_stream: [
      %Samples.ChangeStream.ChangeStreamItem{id: 1, label: "Alpha", value: 10},
      %Samples.ChangeStream.ChangeStreamItem{id: 2, label: "Beta", value: 20},
      %Samples.ChangeStream.ChangeStreamItem{id: 3, label: "Gamma", value: 30}
    ],
    live_feed: [
      %Samples.LiveFeed.LiveFeed{author: "system", text: "Feed started"}
    ],
    ticker: %Samples.Ticker.Ticker{count: 0},
    showcase: 0
  }

  def start_link(_opts), do: Agent.start_link(fn -> @initial end, name: __MODULE__)

  @doc "Reads a key."
  def get(key), do: Agent.get(__MODULE__, &Map.fetch!(&1, key))

  @doc "Changes a key and notifies the observable queries subscribed to `topic`."
  def update(key, topic, fun) do
    Agent.update(__MODULE__, &Map.update!(&1, key, fun))
    Arc.Notifier.notify(App, topic)
  end

  @doc "Puts the initial state back, for tests."
  def reset, do: Agent.update(__MODULE__, fn _ -> @initial end)
end
