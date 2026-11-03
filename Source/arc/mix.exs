# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MixProject do
  use Mix.Project

  @version Path.join(__DIR__, "VERSION")
           |> File.read!()
           |> String.trim()
  @source_url "https://github.com/Cratis/Arc.Elixir"

  def project do
    [
      app: :cratis_arc,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      # Test fixtures define protocol implementations inside test modules, so protocols must
      # not be consolidated before ExUnit loads `test/**/*_test.exs`.
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description:
        "Opinionated CQRS application framework for Phoenix and Plug on Cratis Chronicle, with model-bound commands and queries, validation, authorization, observable queries and opt-in TypeScript proxy generation",
      package: package(),
      source_url: @source_url,
      homepage_url: "https://www.cratis.io/arc/",
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:cratis_chronicle, "~> 3.16"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:websock, "~> 0.5"},
      {:websock_adapter, "~> 0.5"},
      {:telemetry, "~> 1.0"},
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_html, "~> 4.0", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:bandit, "~> 1.5", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "cratis_arc",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Arc" => "https://github.com/Cratis/Arc",
        "Chronicle" => "https://github.com/Cratis/Chronicle",
        "Documentation" => "https://www.cratis.io/arc/",
        "Cratis" => "https://www.cratis.io"
      },
      maintainers: ["Cratis"],
      files: ~w(
        lib
        mix.exs
        README.md
        VERSION
        .formatter.exs
      )
    ]
  end

  defp docs do
    [
      main: "Arc",
      extras: ["README.md"],
      groups_for_modules: [
        Authoring: [Arc.Command, Arc.ReadModel, Arc.Schema, Arc.Validation, Arc.ValidationResult],
        Runtime: [Arc.Application, Arc.Context, Arc.Principal, Arc.Pipeline, Arc.Notifier],
        Hosting: [Arc.Plug, Arc.Plug.Hub, Arc.Plug.SinglePage, Arc.Authentication],
        Phoenix: [Arc.LiveView, Arc.LiveView.Form],
        "Proxy generation": [Arc.ProxyGenerator],
        Testing: [Arc.Test]
      ]
    ]
  end
end
