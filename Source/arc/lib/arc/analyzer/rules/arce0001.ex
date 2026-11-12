# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Rules.ARCE0001 do
  @moduledoc """
  `ARCE0001` - a command-shaped module does not `use Arc.Command`.

  A module with an `Arc.Schema` and a `handle/2` function looks like a command, but Arc only
  discovers modules that `use Arc.Command`, so it is never routed or proxied. The Elixir
  counterpart of the .NET `ARC0002` rule. Kind: module.
  """

  @behaviour Arc.Analyzer.Rule

  alias Arc.Analyzer.Finding

  @impl true
  def id, do: "ARCE0001"

  @impl true
  def description, do: "A module declares a schema and handle/2 but does not use Arc.Command"

  @impl true
  def default_severity, do: :warning

  @impl true
  def check_module(%{kind: nil, schema?: true, handle?: true} = fact, _project) do
    [
      %Finding{
        module: fact.module,
        file: fact.file,
        line: fact.line,
        message:
          "#{inspect(fact.module)} declares a schema and handle/2 but does not `use Arc.Command`, " <>
            "so Arc never discovers it. Replace `use Arc.Schema` with `use Arc.Command`, " <>
            "or rename handle/2 if the module is not a command."
      }
    ]
  end

  def check_module(_fact, _project), do: []
end
