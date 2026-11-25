# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Availability.Paths do
  @moduledoc """
  The paths a part is suspended by, the same as in Arc for .NET: the module, feature and slice of the
  part that are not empty, followed by the full name of the part, joined with `/`.
  """

  @doc "The path of a part."
  @spec for_part(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def for_part(module, feature, slice, name) do
    case Enum.reject([module, feature, slice], &(&1 == "")) do
      [] -> name
      location -> Enum.join(location, "/") <> "/" <> name
    end
  end

  @doc """
  Whether a suspended path covers a part: it equals the part path, is a whole-segment prefix of it,
  or equals the full name of the part.
  """
  @spec covers?(String.t(), String.t(), String.t()) :: boolean()
  def covers?(path, part_path, name),
    do: part_path == path or String.starts_with?(part_path, path <> "/") or name == path
end
