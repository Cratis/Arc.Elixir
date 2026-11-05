# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.ChangeStream.RemoveChangeStreamItem do
  @moduledoc "Removes an item."

  use Arc.Command
  allow_anonymous()

  schema do
    field :id, :integer, required: true
  end

  def handle(%__MODULE__{id: id}, _ctx) do
    Samples.Store.update(:change_stream, "change-stream", fn items ->
      Enum.reject(items, &(&1.id == id))
    end)

    {:ok, nil}
  end
end
