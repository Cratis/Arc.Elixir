# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Counters.Counter do
  @moduledoc "A counter's current value, kept current by Chronicle."

  use Chronicle.ReadModels.ReadModel

  defstruct id: "", value: 0

  from(Counters.CounterIncremented, set: [id: :event_source_id], add: [value: :by])
end
