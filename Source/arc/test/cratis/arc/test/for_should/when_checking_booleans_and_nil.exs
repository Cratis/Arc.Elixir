# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForShould.WhenCheckingBooleansAndNil do
  use ExUnit.Case, async: true

  import Cratis.Arc.Test.Should

  test "should accept exactly true and exactly false" do
    assert {true, false} == {should_be_true(true), should_be_false(false)}
  end

  test "should not treat a truthy value as true" do
    assert_raise ExUnit.AssertionError, ~r/to be true/, fn -> should_be_true(1) end
  end

  test "should not treat nil as false" do
    assert_raise ExUnit.AssertionError, ~r/to be false/, fn -> should_be_false(nil) end
  end

  test "should accept nil, and fail for a value" do
    assert nil == should_be_nil(nil)
    assert_raise ExUnit.AssertionError, ~r/to be nil/, fn -> should_be_nil(:value) end
  end

  test "should return a value that is not nil, and fail for nil" do
    assert :value == should_not_be_nil(:value)
    assert_raise ExUnit.AssertionError, ~r/not to be nil/, fn -> should_not_be_nil(nil) end
  end
end
