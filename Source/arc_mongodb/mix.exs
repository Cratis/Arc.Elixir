# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.MixProject do
  use Mix.Project

  @version Path.join(__DIR__, "VERSION")
           |> File.read!()
           |> String.trim()
  @source_url "https://github.com/Cratis/Arc.Elixir"

  def project do
    [
      app: :cratis_arc_mongodb,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description:
        "MongoDB persistence for Arc on Elixir: tenant-aware databases, BSON conventions and concepts, connection resolution and observable queries over change streams",
      package: package(),
      source_url: @source_url,
      homepage_url: "https://www.cratis.io/arc/",
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      arc_dependency(),
      {:mongodb_driver, "~> 1.6"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.5", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  # In this repository Arc is the sibling package. A published package depends on the same
  # release of `cratis_arc`.
  defp arc_dependency do
    if File.dir?(Path.join(__DIR__, "../arc")),
      do: {:cratis_arc, path: "../arc"},
      else: {:cratis_arc, "~> #{@version}"}
  end

  defp package do
    [
      name: "cratis_arc_mongodb",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Arc" => "https://github.com/Cratis/Arc",
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
      main: "Arc.MongoDB",
      extras: ["README.md"],
      groups_for_modules: [
        Persistence: [Arc.MongoDB, Arc.MongoDB.Document, Arc.MongoDB.Collection],
        Tenancy: [Arc.MongoDB.DatabaseNameResolver, Arc.MongoDB.ServerResolver],
        "Connection resolution": [
          Arc.MongoDB.ConnectionResolver,
          Arc.MongoDB.ConnectionResolver.Http,
          Arc.MongoDB.ConnectionResolver.Template
        ],
        Conventions: [Arc.MongoDB.NamingPolicy, Arc.MongoDB.Codec],
        Observation: [Arc.MongoDB.Watch, Arc.MongoDB.Watcher],
        Testing: [Arc.MongoDB.Test]
      ]
    ]
  end
end
