# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Docs do
  @moduledoc false

  @doc "The first non-empty line of a `@moduledoc` or `@doc` value, used as a one-line summary."
  @spec summary(term()) :: String.t() | nil
  def summary({_line, text}) when is_binary(text), do: summary(text)

  def summary(text) when is_binary(text) do
    text
    |> String.split("\n", trim: true)
    |> List.first()
    |> case do
      nil -> nil
      line -> String.trim(line)
    end
  end

  def summary(_), do: nil
end
