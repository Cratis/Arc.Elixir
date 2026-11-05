# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Showcase.MixProject do
  use Mix.Project

  def project do
    [
      app: :showcase,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      # Opt-in proxy generation: every compile regenerates the TypeScript for the commands and
      # queries. `layout: :colocated` writes each proxy beside the Elixir file it comes from, so a
      # feature's backend, proxies and React page share a folder under `lib`.
      compilers: Mix.compilers() ++ [:arc],
      arc: [application: Samples.Arc, output: "lib", layout: :colocated],
      deps: deps()
    ]
  end

  def application do
    [mod: {Samples.Application, []}, extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:cratis_arc, path: "../../Source/arc"},
      {:cratis_arc_mongodb, path: "../../Source/arc_mongodb"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"}
    ]
  end
end
