# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.ValidationResult do
  @moduledoc """
  One validation outcome, carried in the command and query result envelopes.

  `reason` is an open set (`"rule"`, `"concurrencyViolation"`, `"constraintViolation"`,
  `"validatorFailed"`, `"dependencyUnavailable"`, `"malformedRequest"`, `"frameworkFailure"`);
  clients must tolerate values added later.
  """

  @enforce_keys [:message]
  defstruct severity: :error,
            message: nil,
            members: [],
            state: nil,
            reason: "rule",
            reason_detail: nil

  @type severity :: :unknown | :information | :warning | :error
  @type t :: %__MODULE__{
          severity: severity(),
          message: String.t(),
          members: [atom() | String.t()],
          state: term(),
          reason: String.t(),
          reason_detail: String.t() | nil
        }

  @doc "The numeric wire value of a severity."
  @spec severity_value(severity()) :: 0..3
  def severity_value(:unknown), do: 0
  def severity_value(:information), do: 1
  def severity_value(:warning), do: 2
  def severity_value(:error), do: 3

  @doc "Converts a result to its wire map."
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = result) do
    base = %{
      "severity" => severity_value(result.severity),
      "message" => result.message,
      "members" => Enum.map(result.members, &member_name/1),
      "reason" => result.reason
    }

    base
    |> put_unless_nil("state", result.state)
    |> put_unless_nil("reasonDetail", result.reason_detail)
  end

  defp member_name(member) when is_atom(member), do: Arc.Naming.camel(member)
  defp member_name(member), do: to_string(member)

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)
end
