# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Counters.Counting.Counters do
  @moduledoc "Queries over counters."

  use Arc.ReadModel, model: Counters.Counter, types: [id: :uuid]

  @query params: [id: :uuid], many: false
  def counter(%{id: id}, ctx), do: Chronicle.read_model(Counters.Counter, id, ctx.chronicle)

  @observe params: [id: :uuid], many: false, watch: [Counters.Counter]
  def live_counter(%{id: id}, ctx), do: Chronicle.read_model(Counters.Counter, id, ctx.chronicle)
end
