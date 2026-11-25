# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Availability.Declaration do
  @moduledoc """
  Turns the words of a declaration into the gate expression the engine decides.

  A declaration is a keyword list, one line per key, and every line holds:

    * `for:` - an audience, or a list of audiences of which one is enough
    * `not:` - an audience, or a list of audiences none of which may be held
    * `with:` - a named block, or a list of blocks
    * `when:` - a condition: restricted data from `Cratis.Arc.Availability.Condition` or a module
      implementing that behaviour

  The same words are used on a command, a read model, a query, a scope, and in a block.
  """

  @keys [:for, :not, :with, :when]

  @doc "The expression of the declaration lines, or `nil` when there are none."
  @spec gate([keyword()] | keyword()) :: map() | nil
  def gate([]), do: nil

  def gate(lines) do
    lines = if Keyword.keyword?(lines), do: [lines], else: lines

    case Enum.flat_map(lines, &line/1) do
      [] -> nil
      [one] -> one
      many -> %{"kind" => "all", "items" => many}
    end
  end

  defp line(opts) do
    unknown = Keyword.keys(opts) -- @keys

    if unknown != [] do
      raise ArgumentError,
            "unknown availability word #{inspect(hd(unknown))}; expected one of #{inspect(@keys)}"
    end

    for {key, value} <- opts, expression <- expressions(key, value), do: expression
  end

  defp expressions(:for, audiences) do
    case audience_list(audiences) do
      [one] ->
        [%{"kind" => "for", "audience" => one}]

      many ->
        [%{"kind" => "any", "items" => Enum.map(many, &%{"kind" => "for", "audience" => &1})}]
    end
  end

  defp expressions(:not, audiences),
    do: for(a <- audience_list(audiences), do: %{"kind" => "not", "audience" => a})

  defp expressions(:with, blocks),
    do: for(b <- audience_list(blocks), do: %{"kind" => "with", "block" => b})

  defp expressions(:when, condition),
    do: [%{"kind" => "when", "condition" => condition(condition)}]

  defp audience_list(value), do: value |> List.wrap() |> Enum.map(&to_string/1)

  defp condition(%{"kind" => _} = data), do: data

  defp condition(module) when is_atom(module) do
    unless match?({:module, _}, Code.ensure_compiled(module)) and
             function_exported?(module, :evaluate, 1) do
      raise ArgumentError,
            "#{inspect(module)} is not an availability condition: implement Cratis.Arc.Availability.Condition"
    end

    description =
      if function_exported?(module, :description, 0), do: module.description(), else: ""

    %{"kind" => "named", "name" => inspect(module), "description" => description}
  end

  defp condition(other),
    do: raise(ArgumentError, "a `when` is condition data or a module, got #{inspect(other)}")
end
