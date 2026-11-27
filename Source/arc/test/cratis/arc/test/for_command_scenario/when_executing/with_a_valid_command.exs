# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForCommandScenario.WhenExecuting.WithAValidCommand do
  use Cratis.Arc.Test.CommandScenario,
    application: ArcFixtures.App,
    event_types: [ArcFixtures.Authors.AuthorRegistered]

  alias ArcFixtures.Authors.{AuthorId, AuthorRegistered}
  alias ArcFixtures.Authors.Registration.RegisterAuthor

  @id "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"

  setup_all %{scenario: scenario} do
    %{scenario: execute(scenario, %RegisterAuthor{id: struct(AuthorId, value: @id), name: "Ada"})}
  end

  test("should be successful", %{scenario: scenario}, do: should_be_successful(scenario))

  test "should append the author as registered, for the key event source", %{scenario: scenario} do
    should_have_appended(scenario, %AuthorRegistered{name: "Ada"}, event_source_id: @id)
  end

  test "should append exactly that event", %{scenario: scenario} do
    should_have_appended_exactly(scenario, [AuthorRegistered])
  end

  test "should not append another kind of event", %{scenario: scenario} do
    should_not_have_appended(scenario, fn event -> event.name == "Grace" end)
  end
end
