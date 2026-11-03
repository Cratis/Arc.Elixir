# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Wire do
  @moduledoc """
  Converts Elixir values to the JSON-ready shape of the Arc wire format.

  Struct and map keys become `camelCase`; `Chronicle.Concept` values become the primitive they
  wrap; dates and times become ISO 8601 strings; `nil` stays `nil`.
  """

  @doc "Encodes `term` to a value `Jason` can encode."
  @spec encode(term()) :: term()
  def encode(nil), do: nil
  def encode(value) when is_boolean(value) or is_number(value) or is_binary(value), do: value
  def encode(value) when is_atom(value), do: Atom.to_string(value)
  def encode(%Date{} = value), do: Date.to_iso8601(value)
  def encode(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def encode(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def encode(%Time{} = value), do: Time.to_iso8601(value)
  def encode(%Arc.ValidationResult{} = value), do: Arc.ValidationResult.to_wire(value)

  def encode(%{__struct__: module} = value) do
    if Arc.Types.concept?(module) do
      encode(value.value)
    else
      value |> Map.from_struct() |> encode()
    end
  end

  def encode(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {key_name(key), encode(item)} end)
  end

  def encode(value) when is_list(value), do: Enum.map(value, &encode/1)
  def encode(value) when is_tuple(value), do: value |> Tuple.to_list() |> encode()
  def encode(value), do: inspect(value)

  defp key_name(key) when is_atom(key), do: Arc.Naming.camel(key)
  defp key_name(key) when is_binary(key), do: key
  defp key_name(key), do: to_string(key)
end
