# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.Should do
  @moduledoc """
  Fluent `should_*` assertions for ExUnit, the Elixir counterpart of the `Should` extensions of
  Cratis.Specifications (`ShouldEqual`, `ShouldContain`, `ShouldBeNull`, ...).

  They read as a sentence, take the value under test **first** so they pipe, and return it so
  several can follow one another:

      import Cratis.Arc.Test.Should

      result.response.id
      |> should_not_be_nil()
      |> should_be_of_type(:binary)

      events |> should_contain_only([AuthorRegistered, NameChanged])
      names |> should_contain("Ada") |> should_not_contain("Grace")

  Use them as the **`should_*` assertions** of a spec: `test "should reply with the id"` holds one
  expectation, and the expectation is one `should_*` line. A failure is an `ExUnit.AssertionError`
  that names the expectation and shows both values, so it reads in the ExUnit output like any other.

  `should_match/2` is a macro, so `require` it or `import` this module.

  | Specifications (C#) | Here |
  | --- | --- |
  | `ShouldEqual`, `ShouldNotEqual` | `should_equal/2`, `should_not_equal/2` |
  | `ShouldBeTrue`, `ShouldBeFalse` | `should_be_true/1`, `should_be_false/1` |
  | `ShouldBeNull`, `ShouldNotBeNull` | `should_be_nil/1`, `should_not_be_nil/1` |
  | `ShouldBeEmpty`, `ShouldNotBeEmpty` | `should_be_empty/1`, `should_not_be_empty/1` |
  | `ShouldContain`, `ShouldNotContain` | `should_contain/2`, `should_not_contain/2` |
  | `ShouldContainOnly` | `should_contain_only/2` |
  | `ShouldContainSingleItem` | `should_contain_single_item/1` |
  | `ShouldEachConformTo` | `should_each_conform_to/2` |
  | `ShouldMatch` | `should_match/2` (a pattern) and `should_satisfy/2` (a predicate) |
  | `ShouldBeOfExactType<T>` | `should_be_of_type/2` |
  | `ShouldBeGreaterThan`, `...LessThan`, `...OrEqual` | `should_be_greater_than/2`, `should_be_less_than/2`, `should_be_greater_than_or_equal/2`, `should_be_less_than_or_equal/2` |
  | `ShouldBeInRange`, `ShouldNotBeInRange` | `should_be_in_range/2`, `should_not_be_in_range/2` |
  """

  @type subject :: term()

  # -- equality --------------------------------------------------------------------------------

  @doc "The value should equal `expected` (`===`: `1` does not equal `1.0`)."
  @spec should_equal(subject(), term()) :: subject()
  def should_equal(actual, expected) do
    if actual === expected, do: actual, else: fail("to equal", actual, expected)
  end

  @doc "The value should not equal `unexpected`."
  @spec should_not_equal(subject(), term()) :: subject()
  def should_not_equal(actual, unexpected) do
    if actual !== unexpected, do: actual, else: fail("not to equal", actual, unexpected)
  end

  # -- booleans and nil ------------------------------------------------------------------------

  @doc "The value should be exactly `true`."
  @spec should_be_true(subject()) :: subject()
  def should_be_true(true = actual), do: actual
  def should_be_true(actual), do: fail("to be true", actual, true)

  @doc "The value should be exactly `false`."
  @spec should_be_false(subject()) :: subject()
  def should_be_false(false = actual), do: actual
  def should_be_false(actual), do: fail("to be false", actual, false)

  @doc "The value should be `nil`."
  @spec should_be_nil(subject()) :: nil
  def should_be_nil(nil), do: nil
  def should_be_nil(actual), do: fail("to be nil", actual, nil)

  @doc "The value should not be `nil`."
  @spec should_not_be_nil(subject()) :: subject()
  def should_not_be_nil(nil), do: fail("not to be nil", nil, :not_nil)
  def should_not_be_nil(actual), do: actual

  # -- collections, maps and strings -----------------------------------------------------------

  @doc "The list, map, set or string should be empty."
  @spec should_be_empty(subject()) :: subject()
  def should_be_empty(actual) do
    if empty?(actual), do: actual, else: fail("to be empty", actual, :empty)
  end

  @doc "The list, map, set or string should not be empty."
  @spec should_not_be_empty(subject()) :: subject()
  def should_not_be_empty(actual) do
    if empty?(actual), do: fail("not to be empty", actual, :not_empty), else: actual
  end

  @doc """
  The collection should contain `item`.

  A list, set or range contains an element; a string contains a substring; a map contains a key
  when `item` is not a map and contains a sub-map when it is one (every key with an equal value).
  """
  @spec should_contain(subject(), term()) :: subject()
  def should_contain(actual, item) do
    if contains?(actual, item), do: actual, else: fail("to contain", actual, item)
  end

  @doc "The collection should not contain `item` (see `should_contain/2`)."
  @spec should_not_contain(subject(), term()) :: subject()
  def should_not_contain(actual, item) do
    if contains?(actual, item), do: fail("not to contain", actual, item), else: actual
  end

  @doc """
  The collection should hold exactly `expected`, in any order and with the same duplicates.

      [3, 1, 2] |> should_contain_only([1, 2, 3])
  """
  @spec should_contain_only(Enumerable.t(), Enumerable.t()) :: Enumerable.t()
  def should_contain_only(actual, expected) do
    if Enum.frequencies(actual) == Enum.frequencies(expected),
      do: actual,
      else: fail("to contain only", actual, expected)
  end

  @doc """
  The collection should hold exactly one item, which is returned.

      customer = customers |> should_contain_single_item()
  """
  @spec should_contain_single_item(Enumerable.t()) :: term()
  def should_contain_single_item(actual) do
    case Enum.to_list(actual) do
      [item] -> item
      items -> fail("to contain a single item, got", actual, length(items))
    end
  end

  @doc "Every item of the collection should satisfy `predicate` (a 1-arity function)."
  @spec should_each_conform_to(Enumerable.t(), (term() -> as_boolean(term()))) :: Enumerable.t()
  def should_each_conform_to(actual, predicate) when is_function(predicate, 1) do
    case Enum.reject(actual, predicate) do
      [] -> actual
      offenders -> fail("every item to conform, but these did not:", actual, offenders)
    end
  end

  @doc "The string should start with `prefix`."
  @spec should_start_with(String.t(), String.t()) :: String.t()
  def should_start_with(actual, prefix) when is_binary(actual) and is_binary(prefix) do
    if String.starts_with?(actual, prefix),
      do: actual,
      else: fail("to start with", actual, prefix)
  end

  @doc "The string should end with `suffix`."
  @spec should_end_with(String.t(), String.t()) :: String.t()
  def should_end_with(actual, suffix) when is_binary(actual) and is_binary(suffix) do
    if String.ends_with?(actual, suffix), do: actual, else: fail("to end with", actual, suffix)
  end

  # -- patterns, predicates and types ----------------------------------------------------------

  @doc """
  The value should match `pattern`, and is returned. Variables in the pattern are not bound.

      response |> should_match(%{id: _, secret: %Secret{}})
  """
  defmacro should_match(value, pattern) do
    quote do
      value = unquote(value)

      if match?(unquote(pattern), value),
        do: value,
        else:
          Cratis.Arc.Test.Should.__fail__(
            "to match",
            value,
            {:raw, unquote(Macro.to_string(pattern))}
          )
    end
  end

  @doc "The value should satisfy `predicate` (a 1-arity function)."
  @spec should_satisfy(subject(), (term() -> as_boolean(term()))) :: subject()
  def should_satisfy(actual, predicate) when is_function(predicate, 1) do
    if predicate.(actual), do: actual, else: fail("to satisfy the predicate", actual, :satisfied)
  end

  @type type ::
          module()
          | :atom
          | :binary
          | :bitstring
          | :boolean
          | :float
          | :function
          | :integer
          | :list
          | :map
          | :number
          | :pid
          | :reference
          | :tuple

  @doc """
  The value should be of `type`: a struct module (`%Author{}`), or one of `:atom`, `:binary`,
  `:bitstring`, `:boolean`, `:float`, `:function`, `:integer`, `:list`, `:map`, `:number`, `:pid`,
  `:reference` or `:tuple`.
  """
  @spec should_be_of_type(subject(), type()) :: subject()
  def should_be_of_type(actual, type) do
    if of_type?(actual, type), do: actual, else: fail("to be of type", actual, type)
  end

  # -- comparison ------------------------------------------------------------------------------

  @doc "The value should be greater than `other`."
  @spec should_be_greater_than(subject(), term()) :: subject()
  def should_be_greater_than(actual, other) do
    if actual > other, do: actual, else: fail("to be greater than", actual, other)
  end

  @doc "The value should be greater than or equal to `other`."
  @spec should_be_greater_than_or_equal(subject(), term()) :: subject()
  def should_be_greater_than_or_equal(actual, other) do
    if actual >= other, do: actual, else: fail("to be greater than or equal to", actual, other)
  end

  @doc "The value should be less than `other`."
  @spec should_be_less_than(subject(), term()) :: subject()
  def should_be_less_than(actual, other) do
    if actual < other, do: actual, else: fail("to be less than", actual, other)
  end

  @doc "The value should be less than or equal to `other`."
  @spec should_be_less_than_or_equal(subject(), term()) :: subject()
  def should_be_less_than_or_equal(actual, other) do
    if actual <= other, do: actual, else: fail("to be less than or equal to", actual, other)
  end

  @doc "The value should be within `range` (a `Range`, or a `{min, max}` tuple), both ends included."
  @spec should_be_in_range(subject(), Range.t() | {term(), term()}) :: subject()
  def should_be_in_range(actual, range) do
    if in_range?(actual, range), do: actual, else: fail("to be in the range", actual, range)
  end

  @doc "The value should be outside `range` (see `should_be_in_range/2`)."
  @spec should_not_be_in_range(subject(), Range.t() | {term(), term()}) :: subject()
  def should_not_be_in_range(actual, range) do
    if in_range?(actual, range), do: fail("not to be in the range", actual, range), else: actual
  end

  # -- internals -------------------------------------------------------------------------------

  defp empty?(value) when is_list(value), do: value == []
  defp empty?(value) when is_map(value) and not is_struct(value), do: map_size(value) == 0
  defp empty?(value) when is_binary(value), do: value == ""
  defp empty?(%MapSet{} = value), do: MapSet.size(value) == 0
  defp empty?(value), do: Enum.empty?(value)

  defp contains?(actual, item) when is_binary(actual) and is_binary(item),
    do: String.contains?(actual, item)

  defp contains?(actual, item)
       when is_map(actual) and not is_struct(actual) and is_map(item) and not is_struct(item),
       do: sub_map?(item, actual)

  defp contains?(actual, key) when is_map(actual) and not is_struct(actual),
    do: Map.has_key?(actual, key)

  defp contains?(actual, item), do: Enum.member?(actual, item)

  defp sub_map?(sub, map),
    do: Enum.all?(sub, fn {key, value} -> Map.fetch(map, key) == {:ok, value} end)

  defp of_type?(value, :atom), do: is_atom(value)
  defp of_type?(value, :binary), do: is_binary(value)
  defp of_type?(value, :bitstring), do: is_bitstring(value)
  defp of_type?(value, :boolean), do: is_boolean(value)
  defp of_type?(value, :float), do: is_float(value)
  defp of_type?(value, :function), do: is_function(value)
  defp of_type?(value, :integer), do: is_integer(value)
  defp of_type?(value, :list), do: is_list(value)
  defp of_type?(value, :map), do: is_map(value)
  defp of_type?(value, :number), do: is_number(value)
  defp of_type?(value, :pid), do: is_pid(value)
  defp of_type?(value, :reference), do: is_reference(value)
  defp of_type?(value, :tuple), do: is_tuple(value)
  defp of_type?(%{__struct__: module}, module), do: true
  defp of_type?(_value, _type), do: false

  defp in_range?(value, first..last//_step),
    do: value >= min(first, last) and value <= max(first, last)

  defp in_range?(value, {min, max}), do: value >= min and value <= max

  defp fail(expectation, actual, expected), do: __fail__(expectation, actual, expected)

  @doc false
  @spec __fail__(String.t(), term(), term()) :: no_return()
  def __fail__(expectation, actual, expected) do
    raise ExUnit.AssertionError,
      message:
        "Expected #{inspect(actual, pretty: true, limit: 50)} #{expectation} #{describe(expected)}",
      left: actual,
      right: expected
  end

  defp describe({:raw, text}), do: text
  defp describe(expected), do: inspect(expected, pretty: true, limit: 50)
end
