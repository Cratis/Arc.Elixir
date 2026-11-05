# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.CodecTest do
  use ExUnit.Case, async: true

  alias Arc.MongoDB.{Codec, NamingPolicy}
  alias MongoFixtures.Books.Book

  @none NamingPolicy.None
  @camel NamingPolicy.CamelCase
  @id "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"

  defp book do
    %Book{
      id: @id,
      title: "Dune",
      authors: ["Frank Herbert"],
      published: ~D[1965-08-01],
      added: ~U[2026-01-02 03:04:05.678Z],
      rating: 4.5,
      copies: 3,
      isbn: %MongoFixtures.Isbn{value: "978-0"},
      extra: %{"shelf" => "A", nested: %{n: 1}}
    }
  end

  describe "documents" do
    test "the id is stored as _id, and a uuid as binary subtype 4" do
      document = Codec.to_document(book(), @none)

      assert %BSON.Binary{subtype: :uuid, binary: <<_::binary-size(16)>>} = document["_id"]
      refute Map.has_key?(document, "id")
    end

    test "values are stored as their type says" do
      document = Codec.to_document(book(), @none)

      assert document["title"] == "Dune"
      assert document["authors"] == ["Frank Herbert"]
      assert document["published"] == ~U[1965-08-01 12:00:00Z]
      assert document["added"] == ~U[2026-01-02 03:04:05.678Z]
      assert document["rating"] == 4.5
      assert document["isbn"] == "978-0"
      assert document["extra"] == %{"shelf" => "A", "nested" => %{"n" => 1}}
    end

    test "a stored document comes back as the struct that was written" do
      stored = book() |> Codec.to_document(@none)
      back = Codec.from_document(stored, Book, @none)

      assert back.id == @id
      assert back.published == ~D[1965-08-01]
      assert back.isbn == %MongoFixtures.Isbn{value: "978-0"}
      assert back.added == ~U[2026-01-02 03:04:05.678Z]
      assert %{back | extra: %{}} == %{book() | extra: %{}}
    end

    test "members the struct does not know are ignored and missing ones take the defaults" do
      back = Codec.from_document(%{"title" => "Dune", "mystery" => 1}, Book, @none)

      assert back.title == "Dune"
      assert back.copies == 0
      assert back.authors == []
    end

    test "a list is never nil" do
      shelf = Codec.from_document(%{"label" => "A", "tags" => nil}, MongoFixtures.Shelf, @none)
      assert shelf.tags == nil

      back = Codec.from_document(%{"authors" => nil}, Book, @none)
      assert back.authors == []
    end

    test "an object id is a hexadecimal string in the struct" do
      oid = %BSON.ObjectId{value: :crypto.strong_rand_bytes(12)}
      hex = Base.encode16(oid.value, case: :lower)

      assert Codec.decode(:object_id, oid, @none) == hex
      assert Codec.encode(:object_id, hex, @none) == oid
    end
  end

  describe "naming policies" do
    test "none keeps the names, camel case follows the wire" do
      shelf = %MongoFixtures.Shelf{id: "x", label: "L", display_name: "D"}

      assert %{"_id" => "x", "display_name" => "D", "label" => "L"} =
               Codec.to_document(shelf, @none)

      assert %{"_id" => "x", "displayName" => "D"} = Codec.to_document(shelf, @camel)

      assert %MongoFixtures.Shelf{display_name: "D"} =
               Codec.from_document(%{"displayName" => "D"}, MongoFixtures.Shelf, @camel)
    end

    test "collections are named by the policy unless the document names its own" do
      assert Codec.collection_name(MongoFixtures.Shelf, @none) == "Shelf"
      assert Codec.collection_name(MongoFixtures.Shelf, @camel) == "shelf"
      assert Codec.collection_name(MongoFixtures.Shelf, NamingPolicy.SnakeCase) == "shelf"
      assert Codec.collection_name(Book, @camel) == "books"
    end
  end

  describe "filters" do
    test "atoms are fields with their stored names and values, strings pass through" do
      filter =
        Codec.filter(Book, %{"$text" => %{"$search" => "x"}, id: @id, title: "Dune"}, @none)

      assert %{"_id" => %BSON.Binary{subtype: :uuid}, "title" => "Dune"} = filter
      assert filter["$text"] == %{"$search" => "x"}
    end

    test "operators and lists are translated inside a field" do
      filter =
        Codec.filter(
          Book,
          %{published: %{"$gte" => ~D[2000-01-01]}, copies: %{"$in" => [1, 2]}},
          @none
        )

      assert filter["published"] == %{"$gte" => ~U[2000-01-01 12:00:00Z]}
      assert filter["copies"] == %{"$in" => [1, 2]}
    end

    test "$or and $and translate their clauses" do
      filter = Codec.filter(Book, %{"$or" => [%{title: "A"}, %{copies: 2}]}, @none)
      assert filter == %{"$or" => [%{"title" => "A"}, %{"copies" => 2}]}
    end

    test "a field that does not exist is an error, not an empty result" do
      assert_raise ArgumentError, ~r/no field :nope/, fn ->
        Codec.filter(Book, %{nope: 1}, @none)
      end
    end

    test "sorting and updates use stored names" do
      assert Codec.sort(Book, [title: :asc, copies: :desc], @none) == [
               {"title", 1},
               {"copies", -1}
             ]

      assert Codec.update(
               Book,
               %{"$set" => %{id: @id, title: "X"}, "$inc" => %{copies: 1}},
               @none
             ) ==
               %{
                 "$set" => %{"_id" => Codec.encode(:uuid, @id, @none), "title" => "X"},
                 "$inc" => %{"copies" => 1}
               }
    end
  end
end
