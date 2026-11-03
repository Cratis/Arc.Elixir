# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Counters.MixProject do
  use Mix.Project

  def project do
    [
      app: :counters,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps()
    ]
  end

  def application do
    [mod: {Counters.Application, []}, extra_applications: [:logger]]
  end

  defp deps do
    [
      {:cratis_arc, path: "../../Source/arc"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"}
    ]
  end
end
