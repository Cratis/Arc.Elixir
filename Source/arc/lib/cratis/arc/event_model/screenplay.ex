# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.EventModel.Screenplay do
  @moduledoc false

  # Writes the slices of an application as Cratis Screenplay text: modules, features and slices
  # holding the events, commands, read models, queries and reactions the application declares. It is
  # what the explorer's Source tab shows, so the document can be read, kept and opened in the
  # Screenplay tooling. It states what the code states and nothing more: no handler bodies, no
  # authorization or validation messages.

  alias Cratis.Arc.{Descriptor, Naming}

  @slice_types %{0 => "StateChange", 1 => "StateView", 2 => "Automation"}

  @doc "Screenplay text for `[{module, [feature node]}]`; a node is `%{name, slices, children}`."
  @spec emit([{String.t(), [map()]}]) :: String.t()
  def emit(modules) do
    modules
    |> Enum.map(fn {name, features} -> {name, declare_models_once(features)} end)
    |> Enum.map_join("\n", &module/1)
  end

  # A read model is declared once; a later view over the same model only queries it.
  defp declare_models_once(nodes) do
    {nodes, _seen} = walk(nodes, MapSet.new())
    nodes
  end

  defp walk(nodes, seen) do
    Enum.map_reduce(nodes, seen, fn node, seen ->
      {slices, seen} =
        Enum.map_reduce(node.slices, seen, fn slice, seen ->
          if slice.model != nil and MapSet.member?(seen, slice.model),
            do: {Map.put(slice, :declares_model?, false), seen},
            else:
              {Map.put(slice, :declares_model?, true),
               if(slice.model, do: MapSet.put(seen, slice.model), else: seen)}
        end)

      {children, seen} = walk(node.children, seen)
      {%{node | slices: slices, children: children}, seen}
    end)
  end

  defp module({name, features}) do
    ["module ", ident(name), "\n", Enum.map(features, &feature/1)] |> IO.iodata_to_binary()
  end

  defp feature(node, depth \\ 1)
  defp feature(%{name: "", slices: slices}, depth), do: Enum.map(slices, &slice(&1, depth))

  defp feature(%{name: name, slices: slices, children: children}, depth) do
    [
      indent(depth),
      "feature ",
      ident(name),
      "\n",
      Enum.map(slices, &slice(&1, depth + 1)),
      Enum.map(children, &feature(&1, depth + 1))
    ]
  end

  defp slice(slice, depth) do
    pad = indent(depth)

    [
      pad,
      "slice ",
      Map.fetch!(@slice_types, slice.type),
      " ",
      ident(slice.name),
      "\n",
      description(slice.description, depth + 1),
      Enum.map(slice.events, &event(&1, depth + 1)),
      body(slice, depth + 1)
    ]
  end

  defp body(%{type: 0, commands: commands, events: events}, depth),
    do: Enum.map(commands, &command(&1, events, depth))

  defp body(%{type: 1} = slice, depth) do
    model_name = read_model_name(slice)

    [
      if(Map.get(slice, :declares_model?, true),
        do: read_model(slice.model, model_name, depth),
        else: []
      ),
      Enum.map(slice.queries, &query(&1, slice.model, model_name, depth))
    ]
  end

  defp body(%{type: 2, reactors: reactors, external: external, commands: commands} = slice, depth) do
    events = slice.events

    [
      Enum.map(commands, &command(&1, events, depth)),
      Enum.map(
        reactors,
        &reaction(&1, external, depth, Map.get(slice.reactor_names, &1), List.first(commands))
      )
    ]
  end

  # -- constructs ---------------------------------------------------------------------------------

  defp event(%{name: name, schema: schema} = event, depth) do
    [
      indent(depth),
      "event ",
      ident(name),
      "\n",
      properties(schema, Map.get(event, :defaults, %{}), depth + 1)
    ]
  end

  defp command(%Descriptor{} = command, events, depth) do
    pad = indent(depth + 1)

    [
      indent(depth),
      "command ",
      ident(command.name),
      "\n",
      description(command.doc, depth + 1),
      for field <- command.fields do
        [
          pad,
          property_name(field.name),
          " ",
          type(field.type),
          if(field.required? or field.key?, do: "", else: " optional"),
          if(field.key?, do: " identifier", else: ""),
          "\n"
        ]
      end,
      Enum.map(
        events,
        &[pad, "produces ", ident(&1.name), "\n", identifier_clause(command.fields, pad)]
      )
    ]
  end

  # A nested `for id` line: the command's identifier says which stream the event is appended to.
  defp identifier_clause(fields, pad) do
    case Enum.find(fields, & &1.key?) do
      nil -> ""
      field -> [pad, "  for ", property_name(field.name), "\n"]
    end
  end

  defp read_model_name(%{read_models: [%{id: id, name: name} | _]}) when is_binary(id), do: name
  defp read_model_name(_), do: nil

  defp read_model(nil, _name, _depth), do: []

  defp read_model(model, model_name, depth) do
    pad = indent(depth + 1)

    [
      indent(depth),
      "readmodel ",
      ident(model_name || short(model)),
      "\n",
      for field <- Cratis.Arc.Schema.model_fields(model) do
        [
          pad,
          property_name(field.name),
          " ",
          type(field.type),
          if(field.nullable?, do: " optional", else: ""),
          "\n"
        ]
      end
    ]
  end

  defp query(query, model, model_name, depth) do
    pad = indent(depth + 1)
    returns = if model, do: ident(model_name || short(model)), else: "String"

    [
      indent(depth),
      "query ",
      Naming.pascal(query.name),
      " => ",
      if(query.observable?, do: "observable ", else: ""),
      returns,
      if(query.many?, do: "[]", else: ""),
      "\n",
      for param <- query.params || [] do
        [pad, "filter ", Naming.camel(param.name), " ", type(param.type), " optional\n"]
      end
    ]
  end

  defp reaction(module, external, depth, name, invoked \\ nil) do
    pad = indent(depth + 1)

    [
      indent(depth),
      "reaction ",
      ident(name || short(module)),
      "\n",
      external
      |> Enum.with_index()
      |> Enum.map(fn {event, index} ->
        [
          pad,
          "when ",
          ident(event.name),
          "\n",
          if(index == 0, do: invokes(invoked, depth + 2), else: [])
        ]
      end)
    ]
  end

  # The command a reaction runs, for the event source of the event that triggered it.
  defp invokes(nil, _depth), do: []

  defp invokes(command, depth) do
    case Enum.find(command.fields, & &1.key?) do
      nil ->
        [indent(depth), "invokes ", ident(command.name), "\n"]

      key ->
        [
          indent(depth),
          "invokes ",
          ident(command.name),
          "\n",
          indent(depth + 1),
          property_name(key.name),
          " = $eventSourceId\n"
        ]
    end
  end

  defp description(nil, _depth), do: []
  defp description("", _depth), do: []

  defp description(text, depth),
    do: [
      indent(depth),
      "description \"",
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace(~r/\s+/, " "),
      "\"\n"
    ]

  # -- types --------------------------------------------------------------------------------------

  defp properties(%{"properties" => properties}, defaults, depth) when map_size(properties) > 0 do
    for {name, schema} <- Enum.sort_by(properties, &elem(&1, 0)) do
      [
        indent(depth),
        property_name(name),
        " ",
        schema_type(schema, Map.get(defaults, safe_atom(name))),
        "\n"
      ]
    end
  end

  defp properties(_schema, _defaults, _depth), do: []

  # The schema calls every number a number; an integer default says it is an Int.
  defp schema_type(%{"type" => "number"}, default) when is_integer(default), do: "Int"
  defp schema_type(schema, _default), do: schema_type(schema)

  defp safe_atom(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> nil
  end

  defp schema_type(%{"type" => "integer"}), do: "Int"
  defp schema_type(%{"type" => "number"}), do: "Decimal"
  defp schema_type(%{"type" => "boolean"}), do: "Bool"
  defp schema_type(%{"type" => "array", "items" => items}), do: schema_type(items) <> "[]"
  defp schema_type(%{"type" => "string", "format" => "uuid"}), do: "Uuid"
  defp schema_type(%{"type" => "string", "format" => "date-time"}), do: "DateTime"
  defp schema_type(%{"type" => "string", "format" => "date"}), do: "Date"
  defp schema_type(_), do: "String"

  defp type(:integer), do: "Int"
  defp type(:float), do: "Decimal"
  defp type(:boolean), do: "Bool"
  defp type(:uuid), do: "Uuid"
  defp type(:datetime), do: "DateTime"
  defp type(:date), do: "Date"
  defp type({:list, inner}), do: type(inner) <> "[]"

  defp type(module) when is_atom(module) and module not in [:string, :map] do
    if Cratis.Arc.Types.concept?(module),
      do: type(Cratis.Arc.Types.concept_primitive(module)),
      else: "String"
  end

  defp type(_), do: "String"

  # A name the Screenplay language accepts: `system?` is `system`.
  defp property_name(name), do: name |> Naming.camel() |> String.replace(~r/[^A-Za-z0-9_]/, "")

  defp short(module), do: module |> Module.split() |> List.last()
  defp ident(name), do: name |> to_string() |> String.replace(~r/[^A-Za-z0-9_]/, "")
  defp indent(depth), do: String.duplicate("  ", depth)
end
