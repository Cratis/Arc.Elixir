# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.EventModelHierarchyTest do
  use ExUnit.Case, async: true

  alias Cratis.Arc.EventModel.{Documents, Order, Validation}

  defp event(name, owner),
    do: %{
      name: name,
      event_type: name,
      module: nil,
      owner: owner,
      tags: [],
      schema: %{},
      defaults: %{}
    }

  defp slice(feature, name, type, extra) do
    key = ["M", feature, name]

    base = %{
      key: key,
      module: "M",
      feature: feature,
      name: name,
      type: type,
      description: "",
      status: 0,
      commands: [],
      read_models: [],
      reactors: [],
      reactor_names: %{},
      model: nil,
      queries: [],
      events: [],
      external: [],
      config: []
    }

    Map.merge(base, extra)
  end

  defp change(feature, name, events) do
    key = ["M", feature, name]
    command = %Cratis.Arc.Descriptor{kind: :command, name: name, fields: [], doc: nil}
    slice(feature, name, 0, %{commands: [command], events: Enum.map(events, &event(&1, key))})
  end

  defp view(feature, name, consumes, owners) do
    slice(feature, name, 1, %{
      model: ArcFixtures.Authors.Author,
      external: Enum.map(consumes, &event(&1, Map.fetch!(owners, &1)))
    })
  end

  defp names(slices), do: Enum.map(slices, & &1.name)

  describe "the order" do
    test "a view comes after the slices that produce what it consumes, wherever they are" do
      add = change("Orders.Placing", "Add", ["Added"])
      ship = change("Orders.Shipping", "Ship", ["Shipped"])
      owners = %{"Added" => add.key, "Shipped" => ship.key}
      list = view("Orders.Reading", "List", ["Added", "Shipped"], owners)

      assert names(Order.sort([list, ship, add])) |> Enum.take(-1) == ["List"]
    end

    test "sibling features are ordered by what they depend on, and a feature's slices come before its sub-features" do
      add = change("Orders.Placing", "Add", ["Added"])
      pay = %{slice("Orders.Billing", "Charge", 2, %{}) | external: [event("Added", add.key)]}
      top = change("Orders", "Open", ["Opened"])

      sorted = Order.sort([pay, add, top])

      assert names(sorted) == ["Open", "Add", "Charge"]
    end

    test "a feature is as late as its latest slice" do
      # Grants holds a command and a reaction to events of Credentials, so it follows Credentials.
      add = change("Credentials", "Add", ["Added"])
      set = change("Grants", "Set", ["Set"])

      apply_grants = %{
        slice("Grants", "Apply", 2, %{})
        | external: [event("Added", add.key)],
          events: [event("Applied", ["M", "Grants", "Apply"])]
      }

      assert names(Order.sort([set, apply_grants, add])) == ["Add", "Set", "Apply"]
      assert Validation.check(Order.sort([set, apply_grants, add])) == []
    end

    test "a cycle does not stop the order" do
      a = slice("F", "A", 2, %{external: [event("B", ["M", "F", "B"])]})
      b = slice("F", "B", 2, %{external: [event("A", ["M", "F", "A"])]})

      assert Order.sort([a, b]) |> length() == 2
    end
  end

  describe "the validation" do
    test "a complete model has no problems" do
      add = change("F", "Add", ["Added"])
      list = view("F", "List", ["Added"], %{"Added" => add.key})
      assert Validation.check(Order.sort([list, add])) == []
    end

    test "says what is empty or dangling" do
      empty_change = slice("F", "Lonely", 0, %{})
      blind_view = slice("F", "Blind", 1, %{model: ArcFixtures.Authors.Author})
      silent = slice("F", "Silent", 2, %{external: [event("Gone", nil)]})

      problems = Validation.check([empty_change, blind_view, silent])

      assert Enum.any?(problems, &(&1 =~ "F/Lonely: a state change without a command"))
      assert Enum.any?(problems, &(&1 =~ "F/Lonely: its command appends no events"))
      assert Enum.any?(problems, &(&1 =~ "F/Blind: a view that consumes no events"))
      assert Enum.any?(problems, &(&1 =~ "F/Silent: an automation that records no event"))
      assert Enum.any?(problems, &(&1 =~ "F/Silent: consumes Gone, which no slice produces"))
    end

    test "says when a fact is used before it is produced" do
      add = change("F", "Add", ["Added"])
      list = view("F", "List", ["Added"], %{"Added" => add.key})

      assert [problem] = Validation.check([list, add])
      assert problem =~ "F/List: consumes Added before M/F/Add produces it"
    end
  end

  describe "the documents" do
    setup do
      add = change("Orders.Placing", "Add", ["Added"])
      list = view("Orders.Reading", "List", ["Added"], %{"Added" => add.key})
      top = change("Orders", "Open", ["Opened"])
      slices = Order.sort([list, add, top])
      %{documents: Documents.build(%{name: "App", slices: slices, problems: []}, "app")}
    end

    test "nest sub-features inside their feature", %{documents: [root | _]} do
      [module] = hd(root.model["eventModel"]["collections"])["modules"]
      assert [orders] = module["features"]
      assert orders["name"] == "Orders"
      assert Enum.map(orders["slices"], & &1["name"]) == ["Open"]
      assert Enum.map(orders["subFeatures"], & &1["name"]) == ["Placing", "Reading"]
      assert Enum.map(hd(orders["subFeatures"])["slices"], & &1["name"]) == ["Add"]
    end

    test "have a document for every feature at every depth, each under its parent", %{
      documents: documents
    } do
      by_id = Map.new(documents, &{&1.id, &1})

      assert by_id["app.M.Orders"].parent_id == "app.M"
      assert by_id["app.M.Orders.Placing"].parent_id == "app.M.Orders"
      assert by_id["app.M.Orders.Placing"].namespace == "M.Orders.Placing"
    end

    test "write nested features in the Screenplay source", %{documents: [root | _]} do
      assert root.source =~ "  feature Orders\n"
      assert root.source =~ "    feature Placing\n      slice StateChange Add\n"
      assert root.source =~ "    feature Reading\n      slice StateView List\n"
    end
  end
end
