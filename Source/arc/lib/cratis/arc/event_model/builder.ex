# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.EventModel.Builder do
  @moduledoc false

  # Builds the event model of an Arc application from what it declares: commands and read models
  # from Arc's descriptors, event types, reactors, reducers and projections from Chronicle's
  # discovery, and the events a command appends or a reactor emits from the compiled code (see
  # `Cratis.Arc.EventModel.Appends`).
  #
  # Artifacts are grouped into slices by their module namespace after `segments_to_skip`, the same
  # rule Arc uses for routes and proxy folders: `[module, feature, slice]` with fewer than three
  # segments filling the deepest parts first. A slice with a command is a state change, one with a
  # read model, reducer or projection a state view, and one with only a reactor an automation.

  alias Cratis.Arc.{Descriptor, Naming}
  alias Cratis.Arc.EventModel.Appends

  @state_change 0
  @state_view 1
  @automation 2

  @not_started 0

  @type slice :: %{
          required(:key) => [String.t()],
          required(:name) => String.t(),
          required(:type) => 0 | 1 | 2,
          required(atom()) => term()
        }

  @doc """
  The slices of an application, as `%{module: String.t(), feature: String.t(), slice: slice}`
  entries in a stable order, and the display names of the application.
  """
  @spec build(module()) :: %{name: String.t(), slices: [map()]}
  def build(application) do
    state = Cratis.Arc.Application.state(application)
    config = state.config
    otp_app = Keyword.fetch!(config, :otp_app)
    skip = config[:segments_to_skip]
    chronicle = Cratis.Chronicle.Artifacts.discover(otp_app)
    event_types = chronicle.event_types

    groups =
      []
      |> add_all(state.commands, :commands)
      |> add_all(state.read_models, :read_models)
      |> add_all(chronicle.reactors, :reactors)
      |> add_all(chronicle.reducers, :reducers)
      |> add_all(chronicle.projections, :projections)
      |> add_all(event_types, :events)
      |> group_by_slice(skip)

    slices =
      groups
      |> Enum.flat_map(fn {key, group} ->
        List.wrap(slice(key, group, skip, state, event_types))
      end)
      |> Enum.map(&name_artifacts(&1, skip))
      |> add_model_events(chronicle, skip)
      |> assign_owners()
      |> Cratis.Arc.EventModel.Order.sort()

    %{
      name: otp_app |> to_string() |> Macro.camelize(),
      slices: slices,
      problems: Cratis.Arc.EventModel.Validation.check(slices)
    }
  end

  # A view that shows a model another slice builds (a second read model over the same reducer) still
  # consumes the events that reducer handles, and a read model may declare `consumes:` itself.
  defp add_model_events(slices, chronicle, skip) do
    handled_by_model =
      for module <- chronicle.reducers ++ chronicle.projections,
          model = model_of_module(module),
          not is_nil(model),
          reduce: %{} do
        acc -> Map.update(acc, model, handled(module), &Enum.uniq(&1 ++ handled(module)))
      end

    Enum.map(slices, fn
      %{type: 1} = slice ->
        declared = Enum.flat_map(slice.read_models, & &1.consumes)
        inherited = Map.get(handled_by_model, slice.model, [])
        have = Enum.map(slice.events ++ slice.external, & &1.module)
        missing = Enum.uniq(declared ++ inherited) -- have
        style = slice.config[:display_names] || :pascal_case

        extra =
          missing
          |> events_of()
          |> Enum.map(&name_event(&1, style, skip))

        %{slice | external: slice.external ++ extra}

      slice ->
        slice
    end)
  end

  defp model_of_module(module) do
    cond do
      function_exported?(module, :__chronicle_reducer__, 1) ->
        module.__chronicle_reducer__(:model)

      function_exported?(module, :__chronicle_projection__, 1) ->
        module.__chronicle_projection__(:model)

      true ->
        nil
    end
  end

  # An event belongs to the slice whose command appends it (or that holds its module), so every
  # other slice points at one place.
  defp assign_owners(slices) do
    owners =
      for slice <- slices, event <- slice.events, reduce: %{} do
        acc ->
          candidate = {rank(slice, event), slice.key}
          Map.update(acc, event.event_type, candidate, &min(&1, candidate))
      end

    fix = fn event ->
      case Map.get(owners, event.event_type) do
        {_, key} -> Map.put(event, :owner, key)
        nil -> Map.put(event, :owner, nil)
      end
    end

    Enum.map(slices, fn slice ->
      events = Enum.map(slice.events, fix)
      external = Enum.map(slice.external, fix)

      # A view only consumes: an event it lists that another slice owns is one it reads.
      {mine, theirs} =
        if slice.type == @state_view,
          do: Enum.split_with(events, &(&1.owner == slice.key)),
          else: {events, []}

      %{slice | events: mine, external: Enum.uniq_by(external ++ theirs, & &1.event_type)}
    end)
  end

  # Lower wins: a state change beats an automation and a view, and among those the one that holds
  # the event module beats one that only appends it.
  defp rank(%{type: type, key: key}, %{owner: owner}) do
    {if(type == @state_change, do: 0, else: 1), if(owner == key, do: 0, else: 1)}
  end

  # -- grouping -----------------------------------------------------------------------------------

  defp add_all(acc, items, kind),
    do: Enum.reduce(items, acc, fn item, acc -> [{kind, item} | acc] end)

  defp group_by_slice(entries, skip) do
    entries
    |> Enum.group_by(fn {kind, item} -> key_of(kind, item, skip) end, fn {kind, item} ->
      {kind, item}
    end)
    |> Map.new(fn {key, entries} ->
      {key, Enum.group_by(entries, &elem(&1, 0), &elem(&1, 1))}
    end)
  end

  defp key_of(_kind, %Descriptor{namespace: namespace}, skip),
    do: namespace |> Enum.drop(skip) |> location()

  defp key_of(_kind, module, skip) when is_atom(module) do
    {namespace, _name} = Naming.module_parts(module)
    namespace |> Enum.drop(skip) |> location()
  end

  defp location([]), do: {"", "", ""}
  defp location([a]), do: {"", "", a}
  defp location([a, b]), do: {"", a, b}

  defp location([a | rest]),
    do: {a, rest |> Enum.slice(0..-2//1) |> Enum.join("."), List.last(rest)}

  # -- slices -------------------------------------------------------------------------------------

  defp slice({module, feature, name}, group, skip, state, all_events) do
    commands = Map.get(group, :commands, [])
    read_models = Map.get(group, :read_models, [])
    reactors = Map.get(group, :reactors, [])
    reducers = Map.get(group, :reducers, [])
    projections = Map.get(group, :projections, [])
    owned = Map.get(group, :events, [])

    cond do
      commands != [] and reactors != [] ->
        # A reaction that invokes commands: the automation shows what it reacts to, the command it
        # runs and the events that command appends.
        handles = reactors |> Enum.flat_map(&handled/1) |> Enum.uniq()
        appended = commands |> Enum.flat_map(&Appends.in_module(&1.module)) |> Enum.uniq()

        make(
          module,
          feature,
          name,
          @automation,
          %{
            commands: commands,
            reactors: reactors,
            events: events_of(Enum.uniq(appended ++ owned) -- handles),
            external: events_of(handles)
          },
          skip,
          state
        )

      commands != [] ->
        appended = commands |> Enum.flat_map(&Appends.in_module(&1.module)) |> Enum.uniq()

        make(
          module,
          feature,
          name,
          @state_change,
          %{commands: commands, events: events_of(appended ++ owned)},
          skip,
          state
        )

      read_models != [] or reducers != [] or projections != [] ->
        consumed = (reducers ++ projections) |> Enum.flat_map(&handled/1) |> Enum.uniq()
        external = consumed -- owned

        make(
          module,
          feature,
          name,
          @state_view,
          %{
            read_models: read_models,
            model: model_of(read_models, reducers, projections),
            events: events_of(owned),
            external: events_of(external),
            queries: queries(read_models, state)
          },
          skip,
          state
        )

      reactors != [] ->
        handles = reactors |> Enum.flat_map(&handled/1) |> Enum.uniq()

        emitted =
          reactors |> Enum.flat_map(&Appends.in_module/1) |> Enum.uniq() |> Kernel.--(handles)

        make(
          module,
          feature,
          name,
          @automation,
          %{
            reactors: reactors,
            events: events_of(Enum.uniq(emitted ++ owned) -- handles),
            external: events_of(handles)
          },
          skip,
          state
        )

      true ->
        _ = all_events
        nil
    end
  end

  # Names come from the declared ids (`use Cratis.Arc.Command, id: "..."`, an event type's `id:`, a
  # reactor's `id:`), shown in the configured style, so renaming a module never renames the model.
  defp name_artifacts(slice, skip) do
    style = slice.config[:display_names] || :pascal_case

    %{
      slice
      | commands: Enum.map(slice.commands, &%{&1 | name: Descriptor.display_name(&1, style)}),
        read_models:
          Enum.map(slice.read_models, &%{&1 | name: Descriptor.display_name(&1, style)}),
        events: Enum.map(slice.events, &name_event(&1, style, skip)),
        external: Enum.map(slice.external, &name_event(&1, style, skip))
    }
    |> Map.put(:reactor_names, Map.new(slice.reactors, &{&1, reactor_name(&1, style)}))
    |> Map.put(:style, style)
  end

  defp name_event(%{event_type: id} = event, style, skip) do
    {m, f, s} = key_of(:events, event.module, skip)
    %{event | name: Cratis.Arc.Naming.display(id, style)} |> Map.put(:owner, [m, f, s])
  end

  defp reactor_name(module, style) do
    case module.__chronicle_reactor__(:id) do
      id when is_binary(id) -> Cratis.Arc.Naming.display(id, style)
      _ -> module |> Module.split() |> List.last()
    end
  rescue
    _ -> module |> Module.split() |> List.last()
  end

  defp make(module, feature, name, type, extra, _skip, state) do
    Map.merge(
      %{
        key: [module, feature, name],
        module: module,
        feature: feature,
        name: name,
        type: type,
        description: description(extra),
        status: @not_started,
        commands: [],
        read_models: [],
        reactors: [],
        reactor_names: %{},
        model: nil,
        queries: [],
        events: [],
        external: []
      },
      Map.put(extra, :config, state.config)
    )
  end

  defp description(%{reactors: [module | _]}), do: moduledoc(module)
  defp description(%{commands: [%Descriptor{doc: doc} | _]}) when is_binary(doc), do: doc
  defp description(%{read_models: [%Descriptor{doc: doc} | _]}) when is_binary(doc), do: doc
  defp description(_), do: ""

  defp moduledoc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} -> Cratis.Arc.Docs.summary(doc) || ""
      _ -> ""
    end
  end

  defp handled(module) do
    kind = if function_exported?(module, :__chronicle_reactor__, 1), do: :reactor, else: :reducer

    cond do
      kind == :reactor ->
        module.__chronicle_reactor__(:handles)

      function_exported?(module, :__chronicle_reducer__, 1) ->
        module.__chronicle_reducer__(:handles)

      function_exported?(module, :__chronicle_projection__, 1) ->
        projection_events(module)

      true ->
        []
    end
  end

  defp projection_events(module) do
    from = List.wrap(module.__chronicle_projection__(:from))

    from
    |> Enum.map(fn
      {event, _} -> event
      event -> event
    end)
    |> Enum.filter(&is_atom/1)
  rescue
    _ -> []
  end

  defp model_of(read_models, reducers, projections) do
    reducer = Enum.find_value(reducers, fn m -> m.__chronicle_reducer__(:model) end)
    projection = Enum.find_value(projections, fn m -> m.__chronicle_projection__(:model) end)

    reducer || projection ||
      Enum.find_value(read_models, fn %Descriptor{model: model} -> model end)
  end

  defp queries(read_models, _state) do
    for %Descriptor{queries: queries} <- read_models, q <- queries, do: q
  end

  # -- events -------------------------------------------------------------------------------------

  defp events_of(modules) do
    modules
    |> Enum.uniq()
    |> Enum.filter(
      &(Code.ensure_loaded?(&1) and function_exported?(&1, :__chronicle_event_type__, 1))
    )
    |> Enum.map(fn module ->
      %{
        module: module,
        name: short(module),
        event_type: module.__chronicle_event_type__(:id),
        tags: module.__chronicle_event_type__(:tags) |> List.wrap() |> Enum.map(&to_string/1),
        schema: schema_of(module),
        defaults: defaults_of(module)
      }
    end)
  end

  defp schema_of(module) do
    module |> Cratis.Chronicle.Schemas.JsonSchemaGenerator.generate() |> Jason.decode!()
  rescue
    _ -> %{"type" => "object"}
  end

  defp defaults_of(module) do
    module |> struct() |> Map.from_struct()
  rescue
    _ -> %{}
  end

  defp short(module), do: module |> Module.split() |> List.last()
end
