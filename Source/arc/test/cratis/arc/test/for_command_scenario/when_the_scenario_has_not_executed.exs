# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForCommandScenario.WhenTheScenarioHasNotExecuted do
  use Cratis.Arc.Test.CommandScenario, application: ArcFixtures.App

  test "should say that no command has been executed", %{scenario: scenario} do
    assert_raise ExUnit.AssertionError, ~r/has not executed a command/, fn ->
      should_be_successful(scenario)
    end
  end
end
