# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForShould.WhenComparing do
  use ExUnit.Case, async: true

  import Cratis.Arc.Test.Should

  test "should return the subject when it equals the expected value" do
    assert %{a: 1} == should_equal(%{a: 1}, %{a: 1})
  end

  test "should not treat 1 and 1.0 as equal" do
    assert_raise ExUnit.AssertionError, ~r/to equal/, fn -> should_equal(1, 1.0) end
  end

  test "should show both values when they differ" do
    error = assert_raise ExUnit.AssertionError, fn -> should_equal("a", "b") end
    assert {error.left, error.right} == {"a", "b"}
  end

  test "should return the subject when it differs from the unexpected value" do
    assert 1 == should_not_equal(1, 2)
  end

  test "should fail when it equals the unexpected value" do
    assert_raise ExUnit.AssertionError, ~r/not to equal/, fn -> should_not_equal(1, 1) end
  end

  test "should compare in order" do
    assert 5 ==
             5
             |> should_be_greater_than(4)
             |> should_be_greater_than_or_equal(5)
             |> should_be_less_than(6)
             |> should_be_less_than_or_equal(5)
  end

  test "should fail when the order is wrong" do
    assert_raise ExUnit.AssertionError, ~r/greater than/, fn -> should_be_greater_than(1, 2) end
  end

  test "should know what is in a range" do
    assert 3 ==
             3
             |> should_be_in_range(1..5)
             |> should_be_in_range({3, 3})
             |> should_not_be_in_range(4..9)
  end
end
