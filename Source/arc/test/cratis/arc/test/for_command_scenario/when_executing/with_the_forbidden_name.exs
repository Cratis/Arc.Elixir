# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForCommandScenario.WhenExecuting.WithTheForbiddenName do
  use Cratis.Arc.Test.CommandScenario,
    application: ArcFixtures.App,
    event_types: [ArcFixtures.Authors.AuthorRegistered]

  alias ArcFixtures.Authors.AuthorId
  alias ArcFixtures.Authors.Registration.RegisterAuthor

  setup_all %{scenario: scenario} do
    id = struct(AuthorId, value: "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e")
    %{scenario: execute(scenario, %RegisterAuthor{id: id, name: "forbidden"})}
  end

  test "should say the name is not allowed", %{scenario: scenario} do
    should_have_validation_errors(scenario, "not allowed")
  end
end
