# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForQueryScenario.WhenQuerying do
  use Cratis.Arc.Test.QueryScenario, application: ArcFixtures.App

  alias ArcFixtures.Authors.Listing.Authors

  setup_all %{scenario: scenario} do
    ArcFixtures.Store.start()
    %{scenario: query(scenario, Authors, :all_authors)}
  end

  test("should be successful", %{scenario: scenario}, do: should_be_successful(scenario))

  test("should return nothing when nothing is stored", %{scenario: scenario},
    do: should_return_nothing(scenario)
  )
end
