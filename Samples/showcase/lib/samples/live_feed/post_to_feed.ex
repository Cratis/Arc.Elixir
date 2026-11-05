# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.LiveFeed.PostToFeed do
  @moduledoc """
  Posts a message to the live feed.

  A command whose side effect is observed in real time, over the multiplexed WebSocket or
  Server-Sent Events hub, through the `Samples.LiveFeed.Queries` read model.
  """

  use Arc.Command
  allow_anonymous()
  response Samples.LiveFeed.LiveFeedMessage

  schema do
    field :author, :string, required: true
    field :text, :string, required: true
  end

  alias Samples.{LiveFeed.LiveFeed, LiveFeed.LiveFeedMessage, Store}

  def handle(%__MODULE__{author: author, text: text}, _ctx) do
    now = DateTime.utc_now()

    Store.update(:live_feed, "live-feed", fn feed ->
      feed ++ [%LiveFeed{author: author, text: text, posted_at: now}]
    end)

    {:ok, %LiveFeedMessage{author: author, text: text, posted_at: now}}
  end
end
