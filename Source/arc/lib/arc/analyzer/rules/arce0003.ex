# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Rules.ARCE0003 do
  @moduledoc """
  `ARCE0003` - an `@observe` query has neither `:watch` nor `:topics`.

  An observable query re-runs when something it watches changes. With nothing to watch or
  subscribe to, it runs once per subscription and never again, which is a `@query` with extra
  steps. Kind: module.
  """

  @behaviour Arc.Analyzer.Rule

  alias Arc.Analyzer.Finding

  @impl true
  def id, do: "ARCE0003"

  @impl true
  def description, do: "An @observe query has neither :watch nor :topics"

  @impl true
  def default_severity, do: :warning

  @impl true
  def check_module(%{kind: :read_model, queries: queries} = fact, _project) do
    for %{observable?: true, watch: [], topics: [], name: name} <- queries do
      %Finding{
        module: fact.module,
        file: fact.file,
        line: fact.line,
        message:
          "#{inspect(fact.module)}.#{name}/2 is an @observe query with no :watch and no :topics, " <>
            "so it never pushes an update. Add `watch: [...]` or `topics: [...]`, or use @query."
      }
    end
  end

  def check_module(_fact, _project), do: []
end
