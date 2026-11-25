# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.EventModel.Documents do
  @moduledoc false

  # Turns the slices of `Cratis.Arc.EventModel.Builder` into the documents the explorer lists: one for the
  # whole application (kind "assembly", the root the C# explorer also opens on), one per module and
  # one per feature. Each carries the event model the board draws (the public `@cratis/event-models`
  # document, see `event-model-document.schema.json` in that package) and its Screenplay source.

  alias Cratis.Arc.{Descriptor, Naming}
  alias Cratis.Arc.EventModel.Screenplay

  @doc "The documents of a built application, root first. Each document is a map with `:model` and `:source`."
  @spec build(%{name: String.t(), slices: [map()]}, String.t()) :: [map()]
  def build(%{name: name, slices: slices}, project_id) do
    modules = by_module(slices, name)
    root = project_id

    root_doc =
      document(root, name, "", :assembly, nil, name, modules)

    module_docs =
      for {module, features} <- modules do
        id = "#{project_id}.#{module}"
        document(id, module, module, :module, root, module, [{module, features}])
      end

    feature_docs =
      for {module, nodes} <- modules,
          doc <- feature_documents(nodes, project_id, "#{project_id}.#{module}", module, module) do
        doc
      end

    [root_doc | module_docs ++ feature_docs]
  end

  # One document per feature at every depth; a feature's document holds its sub-features too.
  defp feature_documents(nodes, project_id, parent_id, module, namespace) do
    for %{name: name} = node <- nodes,
        name != "",
        doc <- feature_document(node, project_id, parent_id, module, namespace) do
      doc
    end
  end

  defp feature_document(
         %{name: name, children: children} = node,
         project_id,
         parent_id,
         module,
         namespace
       ) do
    id = "#{parent_id}.#{name}"
    ns = "#{namespace}.#{name}"

    [
      document(id, name, ns, :feature, parent_id, name, [{module, [node]}])
      | feature_documents(children, project_id, id, module, ns)
    ]
  end

  defp by_module(slices, app_name) do
    slices
    |> Enum.uniq_by(&module_name(&1, app_name))
    |> Enum.map(&module_name(&1, app_name))
    |> Enum.map(fn module ->
      in_module = Enum.filter(slices, &(module_name(&1, app_name) == module))
      {module, nodes(in_module, 0)}
    end)
  end

  # The features of a module as a tree, in the order the slices arrive (reading order): `%{name,
  # slices, children}`. Slices without a feature sit in a node with no name.
  defp nodes(slices, depth) do
    {own, deeper} =
      Enum.split_with(slices, &(length(Cratis.Arc.EventModel.Order.path(&1)) == depth))

    names =
      deeper |> Enum.map(&Enum.at(Cratis.Arc.EventModel.Order.path(&1), depth)) |> Enum.uniq()

    own_nodes =
      if own == [],
        do: [],
        else: [%{name: if(depth == 0, do: "", else: nil), slices: own, children: []}]

    children =
      for name <- names do
        group =
          Enum.filter(deeper, &(Enum.at(Cratis.Arc.EventModel.Order.path(&1), depth) == name))

        {own_here, below} =
          Enum.split_with(group, &(length(Cratis.Arc.EventModel.Order.path(&1)) == depth + 1))

        %{name: name, slices: own_here, children: nodes(below, depth + 1)}
      end

    if depth == 0, do: own_nodes ++ children, else: children
  end

  defp module_name(%{module: ""}, app_name), do: app_name
  defp module_name(%{module: module}, _app_name), do: module

  defp document(id, title, namespace, kind, parent, name, modules) do
    model = event_model(id, name, within_scope(modules))

    %{
      id: id,
      title: title,
      namespace: namespace,
      kind: kind,
      parent_id: parent,
      model: %{"eventModel" => model, "errors" => [], "warnings" => [], "success" => true},
      source: Screenplay.emit(modules)
    }
  end

  # A document draws only its own slices, so an event whose producer is outside it points nowhere:
  # it keeps its name and schema and loses the link.
  defp within_scope(modules) do
    keys = for {_module, nodes} <- modules, key <- keys_of(nodes), into: MapSet.new(), do: key

    cut = fn event ->
      if is_nil(event.owner) or MapSet.member?(keys, event.owner),
        do: event,
        else: %{event | owner: nil}
    end

    for {module, nodes} <- modules, do: {module, scope_nodes(nodes, cut)}
  end

  defp keys_of(nodes),
    do: Enum.flat_map(nodes, fn n -> Enum.map(n.slices, & &1.key) ++ keys_of(n.children) end)

  defp scope_nodes(nodes, cut) do
    for node <- nodes do
      slices =
        for slice <- node.slices do
          %{slice | events: Enum.map(slice.events, cut), external: Enum.map(slice.external, cut)}
        end

      %{node | slices: slices, children: scope_nodes(node.children, cut)}
    end
  end

  # -- the board ----------------------------------------------------------------------------------

  defp event_model(id, name, modules) do
    %{
      "id" => guid([id, "model"]),
      "name" => name,
      "collections" => [
        %{
          "id" => guid([id, "collection"]),
          "position" => %{"x" => 0, "y" => 0},
          "modules" =>
            modules
            |> Enum.with_index()
            |> Enum.map(fn {{module, features}, i} -> module_json(id, module, features, i) end),
          "actors" => []
        }
      ],
      "stickyNotes" => [],
      "links" => []
    }
  end

  defp module_json(doc, name, features, index) do
    %{
      "id" => guid([doc, name, "module"]),
      "name" => name,
      "features" => Enum.map(features, &feature_json(doc, name, &1)),
      "collapsed" => false,
      "sortOrder" => index,
      "commentCount" => 0
    }
  end

  defp feature_json(doc, module, %{name: feature, slices: slices, children: children}, path \\ []) do
    path = if feature == "", do: path, else: path ++ [feature]

    %{
      "id" => guid([module, Enum.join(path, "."), "feature"]),
      "name" => if(feature == "", do: module, else: feature),
      "subFeatures" => Enum.map(children, &feature_json(doc, module, &1, path)),
      "slices" =>
        slices |> Enum.with_index() |> Enum.map(fn {slice, i} -> slice_json(doc, slice, i) end),
      "collapsed" => false,
      "rowCollapsed" => false,
      "enabled" => true,
      "commentCount" => 0
    }
  end

  defp slice_json(doc, slice, index) do
    # Slice-level ids do not depend on the document, so an event is the same event in the
    # application, module and feature documents and other slices can point at it.
    _ = doc
    seed = slice.key

    base = %{
      "id" => guid(seed ++ ["slice"]),
      "name" => slice.name,
      "sliceType" => slice.type,
      "description" => slice.description,
      "status" => slice.status,
      "collapsed" => false,
      "sortOrder" => index,
      "externalEvents" => externals_json(seed, slice),
      "events" => events_json(seed, slice),
      "queries" => Enum.map(slice.queries, &query_json(seed, &1)),
      "actors" => [],
      "specifications" => [],
      "commentCount" => 0
    }

    base
    |> put_command(seed, slice.commands)
    |> put_read_model(seed, slice)
    |> put_trigger(slice)
  end

  # What a view or an automation consumes is drawn as the events of the slice, each pointing at the
  # event it came from, which is how the board connects slices.
  defp events_json(seed, %{type: 0} = slice), do: Enum.map(slice.events, &event_json(seed, &1))

  defp events_json(seed, %{type: 1} = slice) do
    Enum.map(slice.events, &event_json(seed, &1)) ++
      for event <- slice.external, do: consumed_json(seed, event)
  end

  defp events_json(seed, slice) do
    Enum.map(slice.events, &event_json(seed, &1))
  end

  defp externals_json(seed, %{type: 2} = slice),
    do: Enum.map(slice.external, &external_json(seed, &1))

  defp externals_json(_seed, _slice), do: []

  # An automation starts from the first event it handles.
  defp put_trigger(json, %{type: 2, external: [%{owner: nil} | _]}) do
    Map.put(json, "automationTrigger", %{"type" => 3, "description" => ""})
  end

  defp put_trigger(json, %{type: 2, external: [event | _]}) do
    Map.put(json, "automationTrigger", %{
      "type" => 1,
      "description" => "",
      "eventId" => event_guid(event)
    })
  end

  defp put_trigger(json, _slice), do: json

  defp event_guid(%{owner: owner, name: name}), do: guid(owner ++ ["event", name])

  defp consumed_json(seed, event) do
    %{
      "id" => guid(seed ++ ["consumed", event.name]),
      "name" => event.name,
      "schema" => event.schema,
      "tags" => event.tags
    }
    |> link(event)
  end

  defp link(json, %{owner: nil}), do: json
  defp link(json, event), do: Map.put(json, "sourceEventId", event_guid(event))

  defp put_command(json, _seed, []), do: json

  defp put_command(json, seed, [%Descriptor{} = command | _]) do
    Map.put(json, "command", %{
      "id" => guid(seed ++ ["command", command.name]),
      "name" => command.name,
      "schema" => Cratis.Arc.Plug.Introspection.schema(command.fields),
      "stateSchema" => %{"type" => "object"},
      "logicDescription" => command.doc || "",
      "rules" => rules(command.fields)
    })
  end

  defp put_read_model(json, seed, %{model: model, read_models: read_models})
       when not is_nil(model) do
    name =
      case read_models do
        [%Descriptor{id: id, name: name} | _] when is_binary(id) -> name
        _ -> model |> Module.split() |> List.last()
      end

    fields = Cratis.Arc.Schema.model_fields(model)

    Map.put(json, "readModel", %{
      "id" => guid(seed ++ ["readModel", name]),
      "name" => name,
      "schema" => Cratis.Arc.Plug.Introspection.schema(fields),
      "materializes" => read_models != [] or true
    })
  end

  defp put_read_model(json, _seed, _slice), do: json

  defp rules(fields) do
    for field <- fields,
        rules = Cratis.Arc.Validation.rules(field.rules_source || []),
        rules != [] do
      %{
        "propertyName" => Naming.camel(field.name),
        "rules" => Enum.map(rules, &%{"ruleType" => &1.name, "errorMessage" => ""})
      }
    end
  end

  # An event the slice owns has the id others point at; one it only shows (a command appending an
  # event of another slice) points at its owner.
  defp event_json(seed, event) do
    base = %{
      "id" => guid(seed ++ ["event", event.name]),
      "name" => event.name,
      "schema" => event.schema,
      "tags" => event.tags
    }

    if event.owner == seed, do: base, else: link(base, event)
  end

  defp external_json(seed, event) do
    %{
      "id" => guid(seed ++ ["external", event.name]),
      "name" => event.name
    }
    |> link(event)
  end

  defp query_json(seed, query) do
    %{
      "id" => guid(seed ++ ["query", Atom.to_string(query.name)]),
      "name" => Naming.pascal(query.name),
      "parameters" =>
        for(
          param <- query.params || [],
          do: %{"name" => Naming.camel(param.name), "type" => parameter_type(param.type)}
        )
    }
  end

  # text 0, number 1, boolean 2, date 3, time 4, unique id 5
  defp parameter_type(type) when type in [:integer, :float], do: 1
  defp parameter_type(:boolean), do: 2
  defp parameter_type(type) when type in [:date, :datetime], do: 3
  defp parameter_type(:uuid), do: 5
  defp parameter_type(_), do: 0

  @doc false
  # A stable GUID from the identity of the thing, so reloading the page draws the same board.
  @spec guid([term()]) :: String.t()
  def guid(parts) do
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
      e::binary-size(12)>> =
      :md5
      |> :crypto.hash(Enum.map_join(parts, "\u0000", &to_string/1))
      |> Base.encode16(case: :lower)

    Enum.join([a, b, c, d, e], "-")
  end
end
