# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Rules do
  @moduledoc """
  The rules that ship with the analyzer.

  | Id | Kind | Default | Checks |
  |----|------|---------|--------|
  | `ARCE0001` | module | warning | A module declares a schema and `handle/2` but does not `use Arc.Command` |
  | `ARCE0002` | module | error | A command or query is both anonymous and restricted |
  | `ARCE0003` | module | warning | An `@observe` query has neither `:watch` nor `:topics` |
  | `ARCE0004` | call | warning | A command appends to Chronicle itself |
  | `ARCE0005` | project | error | Two commands or queries resolve to the same route |
  """

  @rules [
    Arc.Analyzer.Rules.ARCE0001,
    Arc.Analyzer.Rules.ARCE0002,
    Arc.Analyzer.Rules.ARCE0003,
    Arc.Analyzer.Rules.ARCE0004,
    Arc.Analyzer.Rules.ARCE0005
  ]

  @doc "Every shipped rule module."
  @spec all() :: [module()]
  def all, do: @rules
end
