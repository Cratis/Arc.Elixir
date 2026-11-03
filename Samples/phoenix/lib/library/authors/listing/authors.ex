# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Authors.Listing.Authors do
  @moduledoc "Queries over authors."

  # `types:` tells the proxy generator the id is a UUID; the struct default is only a string.
  use Arc.ReadModel, model: Library.Authors.Author, types: [id: :uuid]

  alias Library.Authors.Author

  @doc "All authors."
  @query many: true
  def all_authors(_args, ctx), do: Chronicle.all(Author, ctx.chronicle)

  @doc "One author by id."
  @query params: [id: :uuid], many: false
  def author_by_id(%{id: id}, ctx), do: Chronicle.read_model(Author, id, ctx.chronicle)

  @doc "All authors, kept current: re-runs whenever Chronicle changes an author."
  @observe many: true, watch: [Author]
  def live_authors(_args, ctx), do: Chronicle.all(Author, ctx.chronicle)
end
