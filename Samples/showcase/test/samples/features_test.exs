# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.FeaturesTest do
  # Not async: the store and the Arc application are global.
  use ExUnit.Case

  alias Samples.{ChangeStream, LiveFeed, ObservableCollection, ObservableCollectionWithGuid}
  alias Samples.{QueryShowcase, Store, Ticker}

  setup do
    Store.reset()
    :ok
  end

  defp query(model, name, args \\ %{}, opts \\ []),
    do: Arc.query(Samples.Arc, model, name, args, opts)

  defp execute(command), do: Arc.execute(Samples.Arc, command)

  describe "the ticker" do
    test "is observed with its count and time" do
      assert %{data: %Ticker.Ticker{count: 0}} = query(Ticker.Queries, :observe)

      Store.update(:ticker, "ticker", &%{&1 | count: 5})
      assert %{data: %Ticker.Ticker{count: 5}} = query(Ticker.Queries, :observe)
    end
  end

  describe "the live feed" do
    test "posting returns the message and adds it to the feed" do
      result = execute(%LiveFeed.PostToFeed{author: "ada", text: "hello"})

      assert result.response.author == "ada"
      assert [_system, %{author: "ada", text: "hello"}] = query(LiveFeed.Queries, :all).data
    end

    test "can be narrowed to one author" do
      execute(%LiveFeed.PostToFeed{author: "ada", text: "one"})
      execute(%LiveFeed.PostToFeed{author: "bob", text: "two"})

      assert [%{text: "one"}] = query(LiveFeed.Queries, :by_author, %{author: "ada"}).data
    end

    test "the command needs an author and a text" do
      result = execute(%LiveFeed.PostToFeed{author: "", text: ""})
      refute result.validation_results == []
    end
  end

  describe "the query showcase" do
    test "has the four kinds of query" do
      assert %{data: %{id: 1, name: "Initial"}} = query(QueryShowcase.Queries, :latest)
      assert %{data: [%{name: "Alpha"}, _, _]} = query(QueryShowcase.Queries, :all)
      assert %{data: %{id: 7, name: "Item #7"}} = query(QueryShowcase.Queries, :by_id, %{id: 7})
      assert %{data: items} = query(QueryShowcase.Queries, :get_all)
      assert length(items) == 5
    end

    test "a regular query can be paged and sorted" do
      result =
        query(QueryShowcase.Queries, :get_all, %{},
          page: 1,
          page_size: 2,
          sort_by: "id",
          sort_direction: :desc
        )

      assert Enum.map(result.data, & &1.id) == [3, 2]
      assert result.paging.total_items == 5
    end
  end

  describe "collections" do
    test "add and remove" do
      assert length(query(ObservableCollection.Queries, :all).data) == 2

      execute(%ObservableCollection.AddObservableCollectionItem{id: 3, label: "Three"})
      assert [_, _, %{id: 3, label: "Three"}] = query(ObservableCollection.Queries, :all).data

      execute(%ObservableCollection.RemoveObservableCollectionItem{id: 1})
      assert [%{id: 2}, %{id: 3}] = query(ObservableCollection.Queries, :all).data
    end

    test "with GUID identities" do
      id = Arc.new_id()

      execute(%ObservableCollectionWithGuid.AddObservableCollectionWithGuidItem{
        id: id,
        label: "New"
      })

      assert Enum.any?(query(ObservableCollectionWithGuid.Queries, :all).data, &(&1.id == id))

      execute(%ObservableCollectionWithGuid.RemoveObservableCollectionWithGuidItem{id: id})
      refute Enum.any?(query(ObservableCollectionWithGuid.Queries, :all).data, &(&1.id == id))
    end

    test "the change stream items can be added, updated and removed" do
      execute(%ChangeStream.AddChangeStreamItem{id: 4, label: "Delta", value: 40})
      execute(%ChangeStream.UpdateChangeStreamItem{id: 1, label: "Alpha 2", value: 11})
      execute(%ChangeStream.RemoveChangeStreamItem{id: 2})

      assert [%{id: 1, label: "Alpha 2", value: 11}, %{id: 3}, %{id: 4}] =
               query(ChangeStream.Queries, :all).data
    end
  end

  describe "authentication queries" do
    @queries Samples.AuthenticationQueries.Queries

    test "the anonymous stream is open, the authenticated one needs a caller" do
      assert %{authorized?: true} = query(@queries, :anonymous)
      assert %{authorized?: false} = query(@queries, :authenticated)

      signed_in = Arc.Principal.new("u", "User")

      assert %{authorized?: true} =
               Arc.query(Samples.Arc, @queries, :authenticated, %{}, principal: signed_in)
    end
  end

  describe "cross-cutting authorization" do
    alias Samples.CrossCuttingAuthorization, as: Secured

    defp principal(roles), do: Arc.Principal.new("u", "User", roles: roles)

    test "the filter protects the commands of the namespace" do
      command = %Secured.RunSecuredCommand{message: "hi"}

      denied = Arc.execute(Samples.Arc, command, principal: principal(["User"]))
      refute denied.authorized?
      assert denied.authorization_failure_reason =~ "CrossCuttingAuthorization"

      allowed =
        Arc.execute(Samples.Arc, command, principal: principal(["CrossCuttingAuthorization"]))

      assert allowed.authorized?
      assert allowed.response =~ "— hi"
    end

    test "and its queries" do
      refute Arc.query(Samples.Arc, Secured.Queries, :secured).authorized?

      allowed =
        Arc.query(Samples.Arc, Secured.Queries, :secured, %{},
          principal: principal(["CrossCuttingAuthorization"])
        )

      assert allowed.authorized?
      assert allowed.data.message =~ "cross-cutting filter"
    end

    test "and nothing outside of it" do
      assert Arc.query(Samples.Arc, QueryShowcase.Queries, :get_all).authorized?
    end
  end
end
