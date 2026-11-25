# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Availability.Condition do
  @moduledoc """
  A condition of an availability `when`.

  The restricted form is data, shared with the other Arc implementations and with Screenplay: build
  it with the functions here (`equal/2`, `member?/2`, `all/1`, ...). A path reads the context:
  `"tenant"`, `"identity.user"`, `"arguments.vessel_id"` or `"vessel.package"` for a provided value.

      available when: Cratis.Arc.Availability.Condition.equal("vessel.package", "Plus")

  Anything the restricted form cannot say is a module implementing this behaviour:

      defmodule MyApp.HasPaidInvoice do
        @behaviour Cratis.Arc.Availability.Condition

        @impl true
        def evaluate(read) do
          case read.("account.balance") do
            {:ok, balance} -> if balance <= 0, do: :available, else: :unavailable
            :absent -> :unknown
          end
        end
      end

      available when: MyApp.HasPaidInvoice

  `read` returns `{:ok, value}` or `:absent`. An absent value is `:unknown`, and unknown never opens
  a gate.
  """

  @callback evaluate(read :: (String.t() -> {:ok, term()} | :absent)) ::
              :available | :unavailable | :unknown
  @callback description() :: String.t()
  @optional_callbacks description: 0

  @doc "The value at `path` is `true`."
  def is_true(path), do: compare(path, "isTrue", [])
  @doc "The value at `path` equals `operand`."
  def equal(path, operand), do: compare(path, "equal", [operand])
  @doc "The value at `path` is present and differs from `operand`."
  def not_equal(path, operand), do: compare(path, "notEqual", [operand])
  @doc "The value at `path` is one of `operands`."
  def member?(path, operands) when is_list(operands), do: compare(path, "in", operands)
  @doc "The value at `path` is present and none of `operands`."
  def not_member?(path, operands) when is_list(operands), do: compare(path, "notIn", operands)
  @doc "The value at `path` is greater than `operand`."
  def greater_than(path, operand), do: compare(path, "greaterThan", [operand])
  @doc "The value at `path` is at least `operand`."
  def at_least(path, operand), do: compare(path, "greaterThanOrEqual", [operand])
  @doc "The value at `path` is less than `operand`."
  def less_than(path, operand), do: compare(path, "lessThan", [operand])
  @doc "The value at `path` is at most `operand`."
  def at_most(path, operand), do: compare(path, "lessThanOrEqual", [operand])
  @doc "Every condition holds."
  def all([_ | _] = items), do: %{"kind" => "all", "items" => items}
  @doc "Any condition holds."
  def any([_ | _] = items), do: %{"kind" => "any", "items" => items}

  defp compare(path, operator, operands),
    do: %{"kind" => "compare", "path" => path, "operator" => operator, "operands" => operands}
end
