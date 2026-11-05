# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.LiveFeed.Queries do
  @moduledoc "Queries over the live feed."

  use Arc.ReadModel, model: Samples.LiveFeed.LiveFeed, types: [posted_at: :datetime]
  allow_anonymous()

  alias Samples.Store

  @doc "Observes all messages in the live feed."
  @observe many: true, topics: ["live-feed"]
  def all(_args, _ctx), do: {:ok, Store.get(:live_feed)}

  @doc "Observes the messages posted by one author."
  @observe params: [author: :string], many: true, topics: ["live-feed"]
  def by_author(%{author: author}, _ctx),
    do: {:ok, Enum.filter(Store.get(:live_feed), &(&1.author == author))}
end
