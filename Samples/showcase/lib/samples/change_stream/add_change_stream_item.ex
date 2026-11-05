# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.ChangeStream.AddChangeStreamItem do
  @moduledoc "Adds an item."

  use Arc.Command
  allow_anonymous()

  schema do
    field :id, :integer, required: true
    field :label, :string, required: true
    field :value, :integer, required: true
  end

  def handle(%__MODULE__{id: id, label: label, value: value}, _ctx) do
    item = %Samples.ChangeStream.ChangeStreamItem{id: id, label: label, value: value}
    Samples.Store.update(:change_stream, "change-stream", &(&1 ++ [item]))
    {:ok, nil}
  end
end
