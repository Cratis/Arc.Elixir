# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForShould.WhenMatching do
  use ExUnit.Case, async: true

  import Cratis.Arc.Test.Should

  defmodule Author do
    defstruct name: ""
  end

  test "should return the value when it matches the pattern" do
    assert {:ok, 1} == should_match({:ok, 1}, {:ok, _})
  end

  test "should show the pattern when it does not match" do
    assert_raise ExUnit.AssertionError, ~r/to match {:ok, _}/, fn ->
      should_match(Enum.at([{:error, 1}], 0), {:ok, _})
    end
  end

  test "should match a nested struct pattern" do
    author = %Author{name: "Ada"}
    assert %{author: author} == should_match(%{author: author}, %{author: %Author{name: "Ada"}})
  end

  test "should satisfy a predicate" do
    assert 4 == should_satisfy(4, &(&1 > 3))
    assert_raise ExUnit.AssertionError, ~r/predicate/, fn -> should_satisfy(1, &(&1 > 3)) end
  end

  test "should know the type of a value" do
    assert %Author{} == should_be_of_type(%Author{}, Author)
    assert "x" == should_be_of_type("x", :binary)
  end

  test "should fail for the wrong type" do
    assert_raise ExUnit.AssertionError, ~r/to be of type/, fn -> should_be_of_type(1, :binary) end
  end
end
