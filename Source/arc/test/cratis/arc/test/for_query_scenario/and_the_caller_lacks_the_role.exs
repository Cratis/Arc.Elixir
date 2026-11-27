# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForQueryScenario.AndTheCallerLacksTheRole do
  use Cratis.Arc.Test.QueryScenario, application: ArcFixtures.App

  alias ArcFixtures.Authors.Listing.Authors

  setup_all %{scenario: scenario} do
    %{
      scenario:
        query(scenario, Authors, :secret_authors, %{}, as: principal("tester", ["reader"]))
    }
  end

  test("should not be authorized", %{scenario: scenario}, do: should_not_be_authorized(scenario))
end
