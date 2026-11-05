# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDBTest do
  # Not async: the Arc application and the MongoDB processes are registered by name.
  use MongoFixtures.Case

  alias MongoFixtures.Books.Book

  @a "11111111-1111-4111-8111-111111111111"
  @b "22222222-2222-4222-8222-222222222222"
  @c "33333333-3333-4333-8333-333333333333"

  defp scope(ctx), do: {ctx, Book}

  defp seed(ctx) do
    {:ok, _} =
      Arc.MongoDB.insert_many(scope(ctx), [
        %Book{id: @a, title: "Dune", copies: 3, published: ~D[1965-08-01]},
        %Book{id: @b, title: "Emma", copies: 1, published: ~D[1815-12-23]},
        %Book{id: @c, title: "Ubik", copies: 2, published: ~D[1969-05-01]}
      ])
  end

  describe "reading and writing" do
    test "a document goes in and comes out as the struct", %{ctx: ctx} do
      book = %Book{
        id: @a,
        title: "Dune",
        authors: ["Frank Herbert"],
        added: ~U[2026-01-02 03:04:05.678Z],
        isbn: %MongoFixtures.Isbn{value: "978-0"}
      }

      assert {:ok, ^book} = Arc.MongoDB.insert(scope(ctx), book)
      assert Arc.MongoDB.find_by_id(scope(ctx), @a) == book
      assert Arc.MongoDB.find_by_id(scope(ctx), @b) == nil
    end

    test "the stored form is the convention: _id as UUID binary, dates as dates", %{
      ctx: ctx,
      database: database,
      url: url
    } do
      Arc.MongoDB.insert(scope(ctx), %Book{id: @a, title: "Dune", published: ~D[1965-08-01]})

      conn = Arc.MongoDB.Test.connect(url)
      raw = Mongo.find_one(conn, "books", %{}, database: database)

      assert %BSON.Binary{subtype: :uuid} = raw["_id"]
      assert DateTime.compare(raw["published"], ~U[1965-08-01 12:00:00Z]) == :eq
      assert raw["title"] == "Dune"
    end

    test "find filters, sorts, skips and limits", %{ctx: ctx} do
      seed(ctx)

      assert ["Dune", "Emma", "Ubik"] =
               scope(ctx) |> Arc.MongoDB.all(sort: [title: :asc]) |> titles()

      assert ["Ubik", "Emma", "Dune"] =
               scope(ctx) |> Arc.MongoDB.all(sort: [title: :desc]) |> titles()

      assert ["Emma"] = scope(ctx) |> Arc.MongoDB.find(%{copies: 1}) |> titles()

      assert ["Dune", "Ubik"] =
               scope(ctx)
               |> Arc.MongoDB.find(%{copies: %{"$gte" => 2}}, sort: [title: :asc])
               |> titles()

      assert ["Emma"] =
               scope(ctx)
               |> Arc.MongoDB.find(%{}, sort: [title: :asc], skip: 1, limit: 1)
               |> titles()

      assert ["Dune"] =
               scope(ctx)
               |> Arc.MongoDB.find(%{published: %{"$gt" => ~D[1900-01-01]}, copies: 3})
               |> titles()

      assert %Book{title: "Ubik"} = Arc.MongoDB.find_one(scope(ctx), %{id: @c})
      assert Arc.MongoDB.count(scope(ctx)) == 3
      assert Arc.MongoDB.count(scope(ctx), %{copies: %{"$lt" => 3}}) == 2
    end

    test "sorting by several fields keeps their order", %{ctx: ctx} do
      {:ok, _} =
        Arc.MongoDB.insert_many(scope(ctx), [
          %Book{id: @a, title: "B", copies: 1},
          %Book{id: @b, title: "A", copies: 2},
          %Book{id: @c, title: "A", copies: 1}
        ])

      books = Arc.MongoDB.all(scope(ctx), sort: [title: :asc, copies: :desc])
      assert Enum.map(books, &{&1.title, &1.copies}) == [{"A", 2}, {"A", 1}, {"B", 1}]
    end

    test "save replaces or creates, update changes fields, delete removes", %{ctx: ctx} do
      assert {:ok, _} = Arc.MongoDB.save(scope(ctx), %Book{id: @a, title: "Dune"})
      assert {:ok, _} = Arc.MongoDB.save(scope(ctx), %Book{id: @a, title: "Dune II"})
      assert [%Book{title: "Dune II"}] = Arc.MongoDB.all(scope(ctx))

      assert {:ok, 1} =
               Arc.MongoDB.update(scope(ctx), @a, %{
                 "$set" => %{title: "Messiah"},
                 "$inc" => %{copies: 2}
               })

      assert %Book{title: "Messiah", copies: 2} = Arc.MongoDB.find_by_id(scope(ctx), @a)
      assert {:ok, 0} = Arc.MongoDB.update(scope(ctx), @b, %{"$set" => %{title: "x"}})

      assert {:ok, 1} =
               Arc.MongoDB.update_many(scope(ctx), %{copies: 2}, %{"$set" => %{copies: 5}})

      assert {:ok, 1} = Arc.MongoDB.delete(scope(ctx), @a)
      assert {:ok, 0} = Arc.MongoDB.delete(scope(ctx), @a)
      assert Arc.MongoDB.count(scope(ctx)) == 0
    end

    test "delete_many removes what matches", %{ctx: ctx} do
      seed(ctx)
      assert {:ok, 2} = Arc.MongoDB.delete_many(scope(ctx), %{copies: %{"$gte" => 2}})
      assert ["Emma"] = scope(ctx) |> Arc.MongoDB.all() |> titles()
    end

    test "a duplicate id is reported, not raised", %{ctx: ctx} do
      assert {:ok, _} = Arc.MongoDB.insert(scope(ctx), %Book{id: @a, title: "Dune"})
      assert {:error, :duplicate} = Arc.MongoDB.insert(scope(ctx), %Book{id: @a, title: "Again"})
    end

    test "a unique index turns a violation into :duplicate", %{ctx: ctx} do
      assert :ok = Arc.MongoDB.create_index(scope(ctx), [title: :asc], unique: true)
      assert {:ok, _} = Arc.MongoDB.insert(scope(ctx), %Book{id: @a, title: "Dune"})
      assert {:error, :duplicate} = Arc.MongoDB.insert(scope(ctx), %Book{id: @b, title: "Dune"})
    end
  end

  describe "paging" do
    test "pages and sorts in the database from what the caller asked for", %{ctx: ctx} do
      seed(ctx)

      ctx = %{ctx | query: %{page: 1, page_size: 2, sort_by: "title", sort_direction: :asc}}
      page = Arc.MongoDB.page({ctx, Book}, %{})

      assert %Arc.Page{total: 3, page: 1, size: 2} = page
      assert ["Ubik"] = titles(page.items)
    end

    test "without a page size everything comes back in one page", %{ctx: ctx} do
      seed(ctx)

      page = Arc.MongoDB.page({ctx, Book}, %{}, sort: [title: :desc])
      assert %Arc.Page{total: 3, size: 0} = page
      assert ["Ubik", "Emma", "Dune"] = titles(page.items)
    end

    test "an Arc query returns the page with the paging envelope", %{ctx: ctx} do
      seed(ctx)

      [{descriptor, query}] =
        for d <- Arc.Application.artifacts(MongoFixtures.App).read_models,
            q <- d.queries,
            q.name == :all_books,
            do: {d, q}

      result =
        Arc.Pipeline.execute_query(descriptor, query, %{}, ctx,
          page: 0,
          page_size: 2,
          sort_by: "title",
          sort_direction: :desc
        )

      assert result.paging == %{page: 0, size: 2, total_items: 3}
      assert ["Ubik", "Emma"] = result.data |> titles()
    end
  end

  describe "tenancy" do
    test "a named tenant is a database of its own", %{ctx: ctx, database: database} do
      acme = tenant("acme")
      Arc.MongoDB.insert(scope(ctx), %Book{id: @a, title: "Default's"})
      Arc.MongoDB.insert(scope(acme), %Book{id: @a, title: "Acme's"})

      assert Arc.MongoDB.locate(scope(ctx)) == {database, "books"}
      assert Arc.MongoDB.locate(scope(acme)) == {database <> "+acme", "books"}

      assert ["Default's"] = scope(ctx) |> Arc.MongoDB.all() |> titles()
      assert ["Acme's"] = scope(acme) |> Arc.MongoDB.all() |> titles()
      assert [] = {tenant("globex"), Book} |> Arc.MongoDB.all() |> titles()
    end

    test "the default tenant, in any spelling, is the configured database", %{
      ctx: ctx,
      database: database
    } do
      for spelling <- [nil, "", "Default"] do
        assert Arc.MongoDB.locate({tenant(spelling), Book}) == {database, "books"}
      end

      assert Arc.MongoDB.locate(scope(ctx)) == {database, "books"}
    end

    @tag mongo_options: [database_resolver: Arc.MongoDB.TestResolvers.Prefixed]
    test "a database resolver names the database its own way", %{database: database} do
      assert Arc.MongoDB.locate({tenant("acme"), Book}) == {"acme_" <> database, "books"}
      assert Arc.MongoDB.locate({tenant(nil), Book}) == {database, "books"}
    end

    @tag mongo_options: [naming_policy: :camel_case]
    test "the naming policy names members and collections", %{
      ctx: ctx,
      url: url,
      database: database
    } do
      shelf = %MongoFixtures.Shelf{id: "s1", label: "L", display_name: "D"}
      {:ok, _} = Arc.MongoDB.insert({ctx, MongoFixtures.Shelf}, shelf)

      conn = Arc.MongoDB.Test.connect(url)
      raw = Mongo.find_one(conn, "shelf", %{}, database: database)
      assert raw["displayName"] == "D"
      assert Arc.MongoDB.find_by_id({ctx, MongoFixtures.Shelf}, "s1") == shelf
    end
  end

  describe "configuration" do
    test "an application without MongoDB options says so" do
      defmodule NoMongo do
        use Arc.Application, otp_app: :cratis_arc_mongodb, artifacts: []
      end

      assert_raise ArgumentError, ~r/no :mongodb configuration/, fn ->
        Arc.MongoDB.collection(Arc.context(NoMongo), Book)
      end
    end

    test "server and database are required" do
      assert_raise ArgumentError, ~r/:database/, fn ->
        Arc.MongoDB.Options.build(server: "mongodb://x")
      end

      assert_raise ArgumentError, ~r/:server/, fn -> Arc.MongoDB.Options.build(database: "x") end
    end
  end

  defp titles(books), do: Enum.map(books, & &1.title)
end

defmodule Arc.MongoDB.TestResolvers.Prefixed do
  @behaviour Arc.MongoDB.DatabaseNameResolver

  @impl true
  def resolve(nil, options), do: options.database
  def resolve(tenant, options), do: tenant <> "_" <> options.database
end
