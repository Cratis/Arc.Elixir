# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Ticker.Queries do
  @moduledoc "Queries over the ticker."

  use Arc.ReadModel, model: Samples.Ticker.Ticker, types: [last_updated: :datetime]
  allow_anonymous()

  alias Samples.Store

  @doc "Observes the live counter value. Pushed to every subscriber each time the server ticks."
  @observe many: false, topics: ["ticker"]
  def observe(_args, _ctx), do: {:ok, Store.get(:ticker)}
end
