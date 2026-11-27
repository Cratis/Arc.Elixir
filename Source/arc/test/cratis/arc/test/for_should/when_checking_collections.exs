# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForShould.WhenCheckingCollections do
  use ExUnit.Case, async: true

  import Cratis.Arc.Test.Should

  test "should know what is empty" do
    assert {[], %{}, ""} == {should_be_empty([]), should_be_empty(%{}), should_be_empty("")}
  end

  test "should fail for something that is not empty" do
    assert_raise ExUnit.AssertionError, ~r/to be empty/, fn -> should_be_empty([1]) end
    assert_raise ExUnit.AssertionError, ~r/not to be empty/, fn -> should_not_be_empty([]) end
  end

  test "should find an element in a list, a substring in a string and a key in a map" do
    assert [1, 2] == should_contain([1, 2], 2)
    assert "hello" == should_contain("hello", "ell")
    assert %{a: 1} == should_contain(%{a: 1}, :a)
  end

  test "should find a sub-map in a map" do
    assert %{a: 1, b: 2} == should_contain(%{a: 1, b: 2}, %{a: 1})
    assert_raise ExUnit.AssertionError, ~r/to contain/, fn -> should_contain(%{a: 1}, %{a: 2}) end
  end

  test "should fail when an item is missing, or present but not wanted" do
    assert_raise ExUnit.AssertionError, ~r/to contain/, fn -> should_contain([1], 2) end
    assert_raise ExUnit.AssertionError, ~r/not to contain/, fn -> should_not_contain([1], 1) end
  end

  test "should contain only the expected items, in any order" do
    assert [3, 1, 2] == should_contain_only([3, 1, 2], [1, 2, 3])
  end

  test "should count duplicates when it contains only the expected items" do
    assert_raise ExUnit.AssertionError, ~r/to contain only/, fn ->
      should_contain_only([1, 1, 2], [1, 2])
    end
  end

  test "should return the single item" do
    assert :only == should_contain_single_item([:only])
  end

  test "should fail when there is not exactly one item" do
    assert_raise ExUnit.AssertionError, ~r/single item/, fn ->
      should_contain_single_item([1, 2])
    end
  end

  test "should check every item" do
    assert [2, 4] == should_each_conform_to([2, 4], &(rem(&1, 2) == 0))

    assert_raise ExUnit.AssertionError, ~r/conform/, fn ->
      should_each_conform_to([2, 3], &(rem(&1, 2) == 0))
    end
  end

  test "should check how a string starts and ends" do
    assert "hello" == "hello" |> should_start_with("he") |> should_end_with("lo")
  end
end
