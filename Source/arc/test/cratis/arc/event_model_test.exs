# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.EventModelTest do
  # Application configuration is global, so these specs are not async.
  use ExUnit.Case

  import Plug.Conn
  import Plug.Test

  alias Cratis.Arc.EventModel.{Appends, Builder, Documents}
  alias ArcFixtures.Authors.AuthorRegistered
  alias ArcFixtures.Authors.Registration.RegisterAuthor

  @app ArcFixtures.App

  describe "the events of a command" do
    test "are the event types its code builds" do
      assert Appends.in_module(RegisterAuthor) == [AuthorRegistered]
    end

    test "are empty for a module that builds none" do
      assert Appends.in_module(ArcFixtures.Authors.Author) == []
    end
  end

  describe "the slices of an application" do
    setup do
      %{built: Builder.build(@app)}
    end

    test "a slice with commands is a state change that holds the events they append", %{
      built: built
    } do
      slice = Enum.find(built.slices, &(&1.name == "Registration"))

      assert slice.type == 0

      assert Enum.map(slice.commands, & &1.name) |> Enum.sort() == [
               "Explode",
               "RegisterAuthor",
               "RenameAuthor"
             ]

      assert Enum.map(slice.events, & &1.name) == ["AuthorRegistered"]
    end

    test "a slice with a read model is a state view", %{built: built} do
      slice = Enum.find(built.slices, &(&1.name == "Listing"))

      assert slice.type == 1
      assert slice.model == ArcFixtures.Authors.Author
    end

    test "a reducer makes its model a state view that consumes the events a command appends", %{
      built: built
    } do
      slice = Enum.find(built.slices, &(&1.name == "Authors"))

      assert slice.type == 1
      assert slice.events == []
      assert Enum.map(slice.external, & &1.name) == ["AuthorRegistered"]
      assert hd(slice.external).owner == ["", "Authors", "Registration"]
    end
  end

  describe "the documents" do
    setup do
      %{documents: @app |> Builder.build() |> Documents.build("fixtures")}
    end

    test "are the application, its module and its features, root first", %{documents: documents} do
      [root | rest] = documents

      assert {root.id, root.kind, root.parent_id} == {"fixtures", :assembly, nil}
      assert Enum.all?(rest, &(&1.kind in [:module, :feature]))
      assert Enum.any?(rest, &(&1.kind == :feature and &1.title == "Authors"))
    end

    test "carry the board the explorer draws", %{documents: [root | _]} do
      assert %{"eventModel" => model, "success" => true, "errors" => []} = root.model
      assert [%{"modules" => [module]}] = model["collections"]
      slices = Enum.flat_map(module["features"], & &1["slices"])
      assert Enum.any?(slices, &(&1["name"] == "Registration" and &1["sliceType"] == 0))

      registration = Enum.find(slices, &(&1["name"] == "Registration"))
      assert registration["command"]["name"] in ["Explode", "RegisterAuthor", "RenameAuthor"]
      assert [%{"name" => "AuthorRegistered"}] = registration["events"]
    end

    test "connect a view to the events it consumes and an event to the slice that owns it", %{
      documents: [root | _]
    } do
      slices =
        root.model["eventModel"]["collections"]
        |> Enum.flat_map(& &1["modules"])
        |> Enum.flat_map(& &1["features"])
        |> Enum.flat_map(& &1["slices"])

      ids = for s <- slices, e <- s["events"], not Map.has_key?(e, "sourceEventId"), do: e["id"]

      linked =
        for s <- slices,
            e <- s["events"] ++ s["externalEvents"],
            source = e["sourceEventId"],
            do: source

      assert linked != []
      assert Enum.all?(linked, &(&1 in ids))
    end

    test "carry the Screenplay source", %{documents: [root | _]} do
      assert root.source =~ "slice StateChange Registration"
      assert root.source =~ "command RegisterAuthor"
      assert root.source =~ "produces AuthorRegistered"
      assert root.source =~ "event AuthorRegistered"
    end

    test "identify things the same way every time", %{documents: [root | _]} do
      again = @app |> Builder.build() |> Documents.build("fixtures") |> hd()
      assert again.model == root.model

      assert Documents.guid(["a", "b"]) =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    end
  end

  describe "embedding" do
    @describetag :tmp_dir

    test "writes the catalog and a model and source per document, and only what changed", %{
      tmp_dir: dir
    } do
      {:ok, %{written: first, project: "cratis_arc"}} =
        Cratis.Arc.EventModel.generate(@app, output: dir)

      {:ok, %{written: second}} = Cratis.Arc.EventModel.generate(@app, output: dir)

      assert Enum.any?(first, &String.ends_with?(&1, "catalog.json"))
      assert Enum.any?(first, &String.ends_with?(&1, ".model.json"))
      assert Enum.any?(first, &String.ends_with?(&1, ".screenplay"))
      assert second == []
    end

    test "removes the files of documents that are gone", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "gone.screenplay"), "module Gone")
      {:ok, _} = Cratis.Arc.EventModel.generate(@app, output: dir)

      refute File.exists?(Path.join(dir, "gone.screenplay"))
    end
  end

  describe "the explorer's routes" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      {:ok, _} = Cratis.Arc.EventModel.generate(@app, output: dir)
      previous = Application.get_env(:cratis_arc, @app)
      previous_dirs = Application.get_env(:cratis_arc, :event_model_dirs)
      Application.put_env(:cratis_arc, :event_model_dirs, %{cratis_arc: dir})

      on_exit(fn ->
        restore(@app, previous)
        restore(:event_model_dirs, previous_dirs)
        Cratis.Arc.Application.refresh(@app)
      end)

      configure(introspection: :anonymous, event_model: true)
      :ok
    end

    defp restore(key, nil), do: Application.delete_env(:cratis_arc, key)
    defp restore(key, value), do: Application.put_env(:cratis_arc, key, value)

    defp configure(opts) do
      Application.put_env(:cratis_arc, @app, opts)
      Cratis.Arc.Application.refresh(@app)
    end

    defp call(conn), do: Cratis.Arc.Plug.call(conn, Cratis.Arc.Plug.init(application: @app))
    defp get_path(path), do: :get |> conn(path) |> call()

    test "list the projects and their documents" do
      conn = get_path("/.cratis/event-model/hierarchy")

      assert conn.status == 200

      assert [%{"id" => "cratis_arc", "documents" => [%{"kind" => "assembly"} | _]}] =
               Jason.decode!(conn.resp_body)

      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "serve a document's model and source" do
      model = get_path("/.cratis/event-model/documents/cratis_arc/cratis_arc/model")
      source = get_path("/.cratis/event-model/documents/cratis_arc/cratis_arc/source")

      assert model.status == 200

      assert %{"success" => true, "eventModel" => %{"collections" => [_]}} =
               Jason.decode!(model.resp_body)

      assert source.status == 200
      assert source.resp_body =~ "command RegisterAuthor"
      assert get_resp_header(source, "content-type") |> hd() =~ "text/plain"
    end

    test "answer 404 for a document or a route that does not exist" do
      assert get_path("/.cratis/event-model/documents/cratis_arc/nope/model").status == 404
      assert get_path("/.cratis/event-model/documents/other/cratis_arc/model").status == 404
      assert get_path("/.cratis/event-model/documents/cratis_arc/cratis_arc/other").status == 404
      assert get_path("/.cratis/event-model/nothing").status == 404
    end

    test "redirect to a path with a slash, which the explorer's relative assets need" do
      conn = get_path("/.cratis/event-model")

      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["/.cratis/event-model/"]
    end

    test "never read outside the packaged explorer" do
      assert get_path("/.cratis/event-model/assets/../../mix.exs").status == 404
      assert get_path("/.cratis/event-model/assets/%2e%2e/%2e%2e/mix.exs").status == 404
    end

    test "follow the discovery access setting" do
      configure(introspection: :authenticated, event_model: true)
      assert get_path("/.cratis/event-model/hierarchy").status == 401

      configure(introspection: false, event_model: true)
      refute get_path("/.cratis/event-model/hierarchy").halted
    end

    test "are not served unless switched on, outside development" do
      configure(introspection: :anonymous)
      refute get_path("/.cratis/event-model/hierarchy").halted

      configure(introspection: :anonymous, event_model: false)
      refute get_path("/.cratis/event-model/hierarchy").halted
    end
  end
end
