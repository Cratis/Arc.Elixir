# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Rules.ARCE0005 do
  @moduledoc """
  `ARCE0005` - two commands or queries resolve to the same route.

  Routes come from the module namespace after `segments_to_skip` and the kebab-cased name, so
  `MyApp.Authors.Register` and `Other.Authors.Register` both serve `/api/authors/register`.
  Arc cannot route two commands, or two queries, to one URL, and the generated proxies would collide as well.
  The `segments_to_skip` of the analyzer configuration must match your `Arc.Application`.
  Kind: project.
  """

  @behaviour Arc.Analyzer.Rule

  alias Arc.Analyzer.{Config, Finding}

  @impl true
  def id, do: "ARCE0005"

  @impl true
  def description, do: "Two commands or queries resolve to the same route"

  @impl true
  def default_severity, do: :error

  @impl true
  def check_project(%{modules: modules, config: config}) do
    skip = (config || %Config{}).segments_to_skip

    modules
    |> Map.values()
    |> Enum.flat_map(&routes(&1, skip))
    |> Enum.group_by(fn {route, fact, _what} -> {fact.kind, route} end)
    |> Enum.filter(fn {_route, entries} -> length(entries) > 1 end)
    |> Enum.flat_map(fn {{_kind, route}, entries} ->
      names = entries |> Enum.map(fn {_, _, what} -> what end) |> Enum.sort() |> Enum.join(", ")

      for {_route, fact, what} <- entries do
        %Finding{
          module: fact.module,
          file: fact.file,
          line: fact.line,
          message: "#{what} resolves to #{route}, which is also served by: #{names}. Rename one."
        }
      end
    end)
  end

  defp routes(%{kind: :command, module: module} = fact, skip),
    do: [{route(module, nil, skip), fact, inspect(module)}]

  defp routes(%{kind: :read_model, module: module, queries: queries} = fact, skip),
    do:
      for(
        %{name: name} <- queries,
        do: {route(module, name, skip), fact, "#{inspect(module)}.#{name}/2"}
      )

  defp routes(_fact, _skip), do: []

  defp route(module, query, skip) do
    {namespace, name} = Arc.Naming.module_parts(module)
    last = if query, do: Atom.to_string(query), else: name

    segments = namespace |> Enum.drop(skip) |> Enum.map(&Arc.Naming.kebab/1)
    "/" <> Enum.join(["api" | segments] ++ [Arc.Naming.kebab(last)], "/")
  end
end
