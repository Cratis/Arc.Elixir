# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForCommandScenario.WhenExecuting.WithACommandThatRaises do
  use Cratis.Arc.Test.CommandScenario,
    application: ArcFixtures.App,
    event_types: [ArcFixtures.Authors.AuthorRegistered]

  alias ArcFixtures.Authors.Registration.Explode

  import ExUnit.CaptureLog

  setup_all %{scenario: scenario} do
    me = self()
    log = capture_log(fn -> send(me, {:executed, execute(scenario, %Explode{})}) end)

    receive do
      {:executed, scenario} -> %{scenario: scenario, log: log}
    end
  end

  test "should have the exception, without telling the caller what it was", %{scenario: scenario} do
    should_have_exception(scenario, "unexpected error")
  end

  test("should log what it was", %{log: log}, do: assert(log =~ "boom"))

  test("should not be successful", %{scenario: scenario}, do: should_not_be_successful(scenario))
end
