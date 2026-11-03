# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Counters.CounterIncremented do
  @moduledoc "A counter went up."

  use Chronicle.Events.EventType, id: "counters-counter-incremented"

  defstruct by: 0
end
