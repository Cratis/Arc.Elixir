# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Rules.ARCE0004 do
  @moduledoc """
  `ARCE0004` - a command appends to Chronicle itself.

  A command decides; Arc appends what `handle/2` returns, as `{:append, event}`, with the
  command's key as the event source id, concurrency and constraint handling and the right
  tenant. A direct `Chronicle.append*` call skips all of it. Kind: call.
  """

  @behaviour Arc.Analyzer.Rule

  alias Arc.Analyzer.{Finding, Project}

  @impl true
  def id, do: "ARCE0004"

  @impl true
  def description, do: "A command appends to Chronicle itself"

  @impl true
  def default_severity, do: :warning

  @impl true
  def check_call(%{caller: caller, callee: {module, function, arity} = callee} = call, project) do
    with %{kind: :command} <- Project.module_fact(project, caller),
         true <- append?(callee) do
      [
        %Finding{
          module: caller,
          file: call.file,
          line: call.line,
          message:
            "#{inspect(caller)} is a command and calls #{inspect(module)}.#{function}/#{arity}. " <>
              "Return `{:append, event}` from handle/2 and let Arc append it."
        }
      ]
    else
      _ -> []
    end
  end

  defp append?({module, function, _arity}) do
    name = Atom.to_string(module)

    (name == "Elixir.Chronicle" or String.starts_with?(name, "Elixir.Chronicle.EventSequences")) and
      String.starts_with?(Atom.to_string(function), "append")
  end
end
