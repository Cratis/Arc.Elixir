# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.MixProject do
  use Mix.Project

  def project do
    [
      app: :library,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      # Opt-in proxy generation for the React frontend: every compile regenerates the
      # TypeScript for the commands and queries into the frontend project.
      compilers: Mix.compilers() ++ [:arc],
      arc: [application: Library.Arc, output: "../frontend/src/arc"],
      deps: deps()
    ]
  end

  def application do
    [mod: {Library.Application, []}, extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:cratis_arc, path: "../../Source/arc"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.0"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end
