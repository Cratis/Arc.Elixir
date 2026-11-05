# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.ChangeStream.Queries do
  @moduledoc "Queries over the change stream items."

  use Arc.ReadModel, model: Samples.ChangeStream.ChangeStreamItem
  allow_anonymous()

  @doc "Observes the full collection, pushing every change to subscribers."
  @observe many: true, topics: ["change-stream"]
  def all(_args, _ctx), do: {:ok, Samples.Store.get(:change_stream)}
end
