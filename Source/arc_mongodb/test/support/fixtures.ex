# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule MongoFixtures.Isbn do
  use Chronicle.Concept, type: :string
end

defmodule MongoFixtures.Books.Book do
  use Arc.MongoDB.Document,
    collection: "books",
    types: [id: :uuid, published: :date, added: :datetime, isbn: MongoFixtures.Isbn]

  defstruct id: "",
            title: "",
            authors: [],
            published: nil,
            added: nil,
            rating: 0.0,
            copies: 0,
            isbn: nil,
            extra: %{}
end

defmodule MongoFixtures.Shelf do
  # No `use Arc.MongoDB.Document`: any struct is a document, named by the policy.
  defstruct id: "", label: "", display_name: "", tags: nil
end

defmodule MongoFixtures.Books.Listing.Books do
  @moduledoc "Queries over books."
  use Arc.ReadModel, model: MongoFixtures.Books.Book

  alias MongoFixtures.Books.Book

  @query many: true
  def all_books(_args, ctx), do: {:ok, Arc.MongoDB.page({ctx, Book}, %{})}

  @observe many: true, watch: [Arc.MongoDB.watch(Book)]
  def live_books(_args, ctx), do: {:ok, Arc.MongoDB.all({ctx, Book}, sort: [title: :asc])}
end

defmodule MongoFixtures.App do
  use Arc.Application,
    otp_app: :cratis_arc_mongodb,
    artifacts: [MongoFixtures.Books.Listing.Books]
end
