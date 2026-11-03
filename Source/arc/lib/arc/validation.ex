# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Validation do
  @moduledoc """
  Builds validation results and evaluates declarative field rules.

  Field rules come from `field/3` options in a `schema` block (`required`, `min_length`,
  `max_length`, `email`, `matches`, `min`, `max`, `greater_than`, `less_than`). The same rules
  are written into the generated TypeScript validators, so the browser rejects what the server
  would reject.

  A command can add cross-field rules by defining `validate/2`, returning `:ok` or
  `{:error, results}` built with `error/2`.
  """

  alias Arc.ValidationResult

  @doc """
  Builds an error result for the given members.

      Arc.Validation.error("Already registered", [:name])
  """
  @spec error(String.t(), [atom() | String.t()], keyword()) :: ValidationResult.t()
  def error(message, members \\ [], opts \\ []) do
    %ValidationResult{
      severity: Keyword.get(opts, :severity, :error),
      message: message,
      members: members,
      state: Keyword.get(opts, :state),
      reason: Keyword.get(opts, :reason, "rule"),
      reason_detail: Keyword.get(opts, :reason_detail)
    }
  end

  @doc "Builds a warning result."
  @spec warning(String.t(), [atom() | String.t()], keyword()) :: ValidationResult.t()
  def warning(message, members \\ [], opts \\ []),
    do: error(message, members, Keyword.put(opts, :severity, :warning))

  @doc """
  The client-visible rule descriptors for a field's options, as `%{name: "minLength", args: [3]}`.
  """
  @spec rules(keyword()) :: [map()]
  def rules(opts) do
    []
    |> add_rule(opts[:required], %{name: "notEmpty", args: []})
    |> add_rule(opts[:min_length], fn n -> %{name: "minLength", args: [n]} end)
    |> add_rule(opts[:max_length], fn n -> %{name: "maxLength", args: [n]} end)
    |> add_rule(opts[:email], %{name: "emailAddress", args: []})
    |> add_rule(opts[:matches], fn p -> %{name: "matches", args: [{:regex, p}]} end)
    |> add_rule(opts[:min], fn n -> %{name: "greaterThanOrEqual", args: [n]} end)
    |> add_rule(opts[:max], fn n -> %{name: "lessThanOrEqual", args: [n]} end)
    |> add_rule(opts[:greater_than], fn n -> %{name: "greaterThan", args: [n]} end)
    |> add_rule(opts[:less_than], fn n -> %{name: "lessThan", args: [n]} end)
    |> Enum.reverse()
  end

  defp add_rule(rules, nil, _), do: rules
  defp add_rule(rules, false, _), do: rules
  defp add_rule(rules, true, rule) when is_map(rule), do: [rule | rules]
  defp add_rule(rules, value, fun) when is_function(fun, 1), do: [fun.(value) | rules]

  @doc """
  Evaluates the declarative rules of every field in `fields` against `struct`.
  """
  @spec validate_fields(struct(), [Arc.Schema.Field.t()]) :: [ValidationResult.t()]
  def validate_fields(struct, fields) do
    Enum.flat_map(fields, fn field ->
      value = Map.get(struct, field.name)
      check_field(field, value)
    end)
  end

  defp check_field(field, value) do
    opts = field.rules_source
    name = field.name

    cond do
      opts[:required] && blank?(value) ->
        [error("'#{Arc.Naming.camel(name)}' must not be empty.", [name])]

      is_nil(value) ->
        []

      true ->
        Enum.flat_map(rules(opts), &check_rule(&1, name, value))
    end
  end

  defp check_rule(%{name: "notEmpty"}, _name, _value), do: []

  defp check_rule(%{name: "minLength", args: [n]}, name, value) when is_binary(value),
    do: fail_unless(String.length(value) >= n, "must be at least #{n} characters long.", name)

  defp check_rule(%{name: "maxLength", args: [n]}, name, value) when is_binary(value),
    do: fail_unless(String.length(value) <= n, "must be at most #{n} characters long.", name)

  defp check_rule(%{name: "emailAddress"}, name, value) when is_binary(value),
    do:
      fail_unless(
        Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, value),
        "must be a valid email address.",
        name
      )

  defp check_rule(%{name: "matches", args: [{:regex, p}]}, name, value) when is_binary(value),
    do: fail_unless(Regex.match?(Regex.compile!(p), value), "has an invalid format.", name)

  defp check_rule(%{name: "greaterThanOrEqual", args: [n]}, name, value) when is_number(value),
    do: fail_unless(value >= n, "must be greater than or equal to #{n}.", name)

  defp check_rule(%{name: "lessThanOrEqual", args: [n]}, name, value) when is_number(value),
    do: fail_unless(value <= n, "must be less than or equal to #{n}.", name)

  defp check_rule(%{name: "greaterThan", args: [n]}, name, value) when is_number(value),
    do: fail_unless(value > n, "must be greater than #{n}.", name)

  defp check_rule(%{name: "lessThan", args: [n]}, name, value) when is_number(value),
    do: fail_unless(value < n, "must be less than #{n}.", name)

  defp check_rule(_rule, _name, _value), do: []

  defp fail_unless(true, _message, _name), do: []

  defp fail_unless(false, message, name),
    do: [error("'#{Arc.Naming.camel(name)}' #{message}", [name])]

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(%{value: value}), do: blank?(value)
  defp blank?(_), do: false
end
