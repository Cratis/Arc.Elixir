# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

Code.require_file("../given/an_author.exs", __DIR__)

defmodule Cratis.Arc.Test.ForGiven.WhenExecuting.WithGivenContexts do
  use Cratis.Arc.Test.CommandScenario,
    application: ArcFixtures.App,
    event_types: [ArcFixtures.Authors.AuthorRegistered],
    given: [Cratis.Arc.Test.ForGiven.Given.TwoAuthors],
    setup: {Cratis.Arc.Test.ForGiven.Given.Prepared, :prepare}

  alias ArcFixtures.Authors.{AuthorId, AuthorRegistered}
  alias ArcFixtures.Authors.Registration.RegisterAuthor

  @id "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"

  setup_all %{scenario: scenario} do
    %{
      scenario:
        execute(scenario, %RegisterAuthor{id: struct(AuthorId, value: @id), name: "Linus"})
    }
  end

  test("should be successful", %{scenario: scenario}, do: should_be_successful(scenario))

  test "should count only what the command appended", %{scenario: scenario} do
    should_have_appended_exactly(scenario, [%AuthorRegistered{name: "Linus"}])
  end

  test("should have run the setup function first", context,
    do: context.prepared |> should_be_true()
  )
end
