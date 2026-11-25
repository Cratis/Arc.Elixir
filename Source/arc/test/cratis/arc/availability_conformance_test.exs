# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.AvailabilityConformanceTest do
  # Runs the shared availability vectors of Cratis/Arc (pinned in test/support/availability).
  use ExUnit.Case, async: true

  alias Cratis.Arc.Availability.Manifest

  @root Path.expand("../../support/availability", __DIR__)
  @files Path.wildcard(Path.join(@root, "vectors/*.json"))

  test "the vectors were found" do
    assert Enum.any?(Path.wildcard(Path.join(@root, "vectors/*.json")))
  end

  for file <- @files do
    vectors = file |> File.read!() |> Jason.decode!()
    assert vectors["format"] == "cratis-availability-vectors" and vectors["version"] == 1

    for {kase, index} <- Enum.with_index(vectors["cases"]) do
      @kase kase
      @manifest vectors["manifest"]

      test "#{vectors["name"]}: #{kase["name"]} (#{index})" do
        kase = @kase
        assert {:ok, document} = Manifest.decode(@manifest)
        context = kase["context"]

        decision =
          Manifest.decide(
            document,
            kase["part"],
            %{
              tenant: context["tenant"],
              user: context["user"],
              audiences: context["audiences"] || [],
              suspended: context["suspended"] || [],
              values: context["values"] || %{}
            }
            |> then(fn c ->
              if kase["arguments"], do: Map.put(c, :arguments, kase["arguments"]), else: c
            end)
          )

        expect = kase["expect"]
        assert decision.available == expect["available"]
        if expect["reason"], do: assert(decision.reason == expect["reason"])
      end
    end
  end
end
