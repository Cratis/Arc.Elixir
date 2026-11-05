# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Ticker.Ticker do
  @moduledoc "The live counter: how often the server has ticked, and when it did so last."

  defstruct count: 0, last_updated: ~U[1970-01-01 00:00:00Z]
end
