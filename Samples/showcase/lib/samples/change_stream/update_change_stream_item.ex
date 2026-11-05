# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.ChangeStream.UpdateChangeStreamItem do
  @moduledoc "Replaces the label and value of an item."

  use Arc.Command
  allow_anonymous()

  schema do
    field :id, :integer, required: true
    field :label, :string, required: true
    field :value, :integer, required: true
  end

  def handle(%__MODULE__{id: id, label: label, value: value}, _ctx) do
    Samples.Store.update(:change_stream, "change-stream", fn items ->
      Enum.map(items, fn
        %{id: ^id} = item -> %{item | label: label, value: value}
        item -> item
      end)
    end)

    {:ok, nil}
  end
end
