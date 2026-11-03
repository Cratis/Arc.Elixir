# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Counters.Counting.IncrementCounter do
  @moduledoc "Raises a counter by an amount."

  use Arc.Command

  schema do
    field(:id, Counters.CounterId, key: true, required: true)
    field(:by, :integer, required: true, min: 1, max: 100)
  end

  def handle(%__MODULE__{by: by}, _ctx), do: {:append, %Counters.CounterIncremented{by: by}}
end
