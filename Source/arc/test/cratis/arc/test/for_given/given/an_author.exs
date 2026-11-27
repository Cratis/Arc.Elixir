# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.ForGiven.Given.AnAuthor do
  use Cratis.Arc.Test.Given

  alias ArcFixtures.Authors.AuthorRegistered

  @impl true
  def given(scenario),
    do:
      given_events(scenario, "11111111-1111-4111-8111-111111111111", %AuthorRegistered{
        name: "Ada"
      })

  @impl true
  def given(scenario, name),
    do:
      given_events(scenario, "22222222-2222-4222-8222-222222222222", %AuthorRegistered{name: name})
end

defmodule Cratis.Arc.Test.ForGiven.Given.TwoAuthors do
  use Cratis.Arc.Test.Given

  alias Cratis.Arc.Test.ForGiven.Given.AnAuthor

  @impl true
  def given(scenario),
    do: scenario |> given_context(AnAuthor) |> given_context({AnAuthor, "Grace"})
end

defmodule Cratis.Arc.Test.ForGiven.Given.Prepared do
  @moduledoc false
  def prepare(_client), do: %{prepared: true}
end
