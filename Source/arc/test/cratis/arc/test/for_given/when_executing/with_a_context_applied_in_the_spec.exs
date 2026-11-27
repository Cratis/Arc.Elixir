# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../given/an_author.exs", __DIR__)

defmodule Cratis.Arc.Test.ForGiven.WhenExecuting.WithAContextAppliedInTheSpec do
  use Cratis.Arc.Test.CommandScenario,
    application: ArcFixtures.App,
    event_types: [ArcFixtures.Authors.AuthorRegistered]

  alias ArcFixtures.Authors.{AuthorId, AuthorRegistered}
  alias ArcFixtures.Authors.Registration.RegisterAuthor
  alias Cratis.Arc.Test.ForGiven.Given.AnAuthor

  setup_all %{scenario: scenario} do
    scenario =
      scenario
      |> given(AnAuthor)
      |> given(fn scenario ->
        given_events(scenario, "33333333-3333-4333-8333-333333333333", %AuthorRegistered{
          name: "Hopper"
        })
      end)
      |> execute(%RegisterAuthor{
        id: struct(AuthorId, value: "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"),
        name: "Linus"
      })

    %{scenario: scenario}
  end

  test "should not count the given events", %{scenario: scenario} do
    should_not_have_appended(scenario, fn event -> event.name in ["Ada", "Hopper"] end)
  end
end
