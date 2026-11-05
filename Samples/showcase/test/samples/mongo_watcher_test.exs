# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.MongoWatcherTest do
  # Needs a MongoDB replica set: `docker compose up -d`, or MONGODB_URL.
  use ExUnit.Case

  @moduletag :mongodb

  alias Samples.MongoWatcher.{AddWatcherItem, AddWatcherNote, Items, Notes, WatcherItem}

  setup do
    raw = Application.get_env(:showcase, Samples.Arc)
    database = Arc.MongoDB.Test.unique_database("samples_test")
    mongodb = Keyword.put(raw[:mongodb], :database, database)
    Application.put_env(:showcase, Samples.Arc, Keyword.put(raw, :mongodb, mongodb))
    Arc.Application.refresh(Samples.Arc)

    on_exit(fn ->
      Arc.MongoDB.Test.drop_databases(Samples.Arc, database, ["acme", "globex"])
      Application.put_env(:showcase, Samples.Arc, raw)
      Arc.Application.refresh(Samples.Arc)
    end)

    :ok
  end

  defp execute(command, tenant), do: Arc.execute(Samples.Arc, command, tenant: tenant)
  defp names(result), do: Enum.map(result.data, & &1.name)

  test "items are stored per tenant" do
    assert execute(%AddWatcherItem{name: "default's"}, nil).authorized?
    assert execute(%AddWatcherItem{name: "acme's"}, "acme").authorized?

    query = fn tenant ->
      Arc.query(Samples.Arc, Items.Queries, :observe_all, %{}, tenant: tenant)
    end

    assert ["default's"] = names(query.(nil))
    assert ["acme's"] = names(query.("acme"))
    assert [] = names(query.("globex"))
  end

  test "the paged query pages and sorts in the database" do
    for name <- ~w(c a b), do: execute(%AddWatcherItem{name: name}, "acme")

    result =
      Arc.query(Samples.Arc, Items.Queries, :paged, %{},
        tenant: "acme",
        page: 1,
        page_size: 2,
        sort_by: "name",
        sort_direction: :asc
      )

    assert ["c"] = names(result)
    assert result.paging.total_items == 3
  end

  test "a note is stored beside the items" do
    assert execute(%AddWatcherNote{text: "a note"}, "acme").authorized?

    result = Arc.query(Samples.Arc, Notes.Queries, :observe_all, %{}, tenant: "acme")
    assert [%{text: "a note"}] = result.data

    assert {_database, "watcherNote"} =
             Arc.MongoDB.locate(
               {Arc.context(Samples.Arc, tenant: "acme"), Samples.MongoWatcher.WatcherNote}
             )

    assert {_, "watcherItem"} = Arc.MongoDB.locate({Arc.context(Samples.Arc), WatcherItem})
  end
end
