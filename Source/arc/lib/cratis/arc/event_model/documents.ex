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
      for {module, features} <- modules, {feature, slice_list} <- features, feature != "" do
        parent = "#{project_id}.#{module}"
        id = "#{parent}.#{feature}"

        document(id, feature, "#{module}.#{feature}", :feature, parent, feature, [
          {module, [{feature, slice_list}]}
        ])
      end

    [root_doc | module_docs ++ feature_docs]
  end

  defp by_module(slices, app_name) do
    slices
    |> Enum.group_by(&module_name(&1, app_name))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {module, in_module} ->
      features =
        in_module
        |> Enum.group_by(& &1.feature)
        |> Enum.sort_by(&elem(&1, 0))

      {module, features}
    end)
  end

  defp module_name(%{module: ""}, app_name), do: app_name
  defp module_name(%{module: module}, _app_name), do: module

  defp document(id, title, namespace, kind, parent, name, modules) do
    model = event_model(id, name, modules)

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
      "features" =>
        features |> Enum.map(fn {feature, slices} -> feature_json(doc, name, feature, slices) end),
      "collapsed" => false,
      "sortOrder" => index,
      "commentCount" => 0
    }
  end

  defp feature_json(doc, module, feature, slices) do
    %{
      "id" => guid([doc, module, feature, "feature"]),
      "name" => if(feature == "", do: module, else: feature),
      "subFeatures" => [],
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
      "sourceEventId" => event_guid(event),
      "tags" => event.tags
    }
  end

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

    if event.owner == seed, do: base, else: Map.put(base, "sourceEventId", event_guid(event))
  end

  defp external_json(seed, event) do
    %{
      "id" => guid(seed ++ ["external", event.name]),
      "name" => event.name,
      "sourceEventId" => event_guid(event)
    }
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
