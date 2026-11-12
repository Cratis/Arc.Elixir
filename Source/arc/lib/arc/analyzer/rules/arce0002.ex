# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Rules.ARCE0002 do
  @moduledoc """
  `ARCE0002` - a command or query is both anonymous and restricted.

  `allow_anonymous: true` next to `roles:`, `policy:` or `:authenticated` contradicts itself:
  Arc checks `allow_anonymous` first, so the restriction is silently ignored and the artifact
  is open to everyone. The Elixir counterpart of the .NET `ARC0019` rule. Kind: module.
  """

  @behaviour Arc.Analyzer.Rule

  alias Arc.Analyzer.Finding

  @impl true
  def id, do: "ARCE0002"

  @impl true
  def description, do: "A command or query is both anonymous and restricted"

  @impl true
  def default_severity, do: :error

  @impl true
  def check_module(%{kind: kind} = fact, _project) when kind in [:command, :read_model] do
    module = if conflicting?(fact.authorization), do: [{inspect(fact.module), fact}], else: []

    queries =
      for %{authorization: auth, name: name} <- fact.queries,
          conflicting?(auth),
          do: {"#{inspect(fact.module)}.#{name}/2", fact}

    for {subject, fact} <- module ++ queries do
      %Finding{
        module: fact.module,
        file: fact.file,
        line: fact.line,
        message:
          "#{subject} is declared anonymous and also requires authentication, roles or a policy. " <>
            "Arc lets anonymous callers through, so the restriction does nothing. Keep one of them."
      }
    end
  end

  def check_module(_fact, _project), do: []

  defp conflicting?(nil), do: false

  defp conflicting?(auth),
    do: auth.allow_anonymous and (auth.authenticated? or auth.roles != [] or auth.policy != nil)
end
