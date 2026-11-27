# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForCommandScenario.WhenExecuting.AndTheCallerIsAnAdmin do
  use Cratis.Arc.Test.CommandScenario,
    application: ArcFixtures.App,
    event_types: [ArcFixtures.Authors.AuthorRegistered]

  alias ArcFixtures.Authors.Registration.RenameAuthor

  @id "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"

  setup_all %{scenario: scenario} do
    %{
      scenario:
        execute(scenario, %RenameAuthor{id: @id, name: "Ada"}, as: principal("tester", ["admin"]))
    }
  end

  test("should be successful", %{scenario: scenario}, do: should_be_successful(scenario))

  test "should respond with the name it replaced", %{scenario: scenario} do
    should_respond_with(scenario, "previous-" <> @id)
  end
end
