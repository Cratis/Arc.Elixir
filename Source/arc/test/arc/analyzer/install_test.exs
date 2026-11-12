# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @project """
  defmodule MyApp.MixProject do
    use Mix.Project

    def project do
      [
        app: :my_app,
        version: "0.1.0",
        deps: []
      ]
    end
  end
  """

  defp project(mix, files) do
    igniter = test_project(files: files)

    if mix,
      do: Igniter.update_file(igniter, "mix.exs", &Rewrite.Source.update(&1, :content, mix)),
      else: igniter
  end

  defp install(igniter), do: Igniter.compose_task(igniter, "cratis_arc.install", [])

  defp content(igniter, path),
    do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  test "adds the compiler ahead of the default compilers" do
    igniter = project(@project, %{}) |> install()

    assert content(igniter, "mix.exs") =~ "compilers: [:arc_analyzer] ++ Mix.compilers()"
  end

  test "is safe to run twice" do
    once = project(@project, %{}) |> install()
    twice = install(once)

    assert content(once, "mix.exs") == content(twice, "mix.exs")
    assert content(twice, "mix.exs") |> String.split(":arc_analyzer") |> length() == 2
  end

  test "keeps the compilers that are already there" do
    mix =
      String.replace(
        @project,
        "deps: []",
        "compilers: Mix.compilers() ++ [:arc],\n        deps: []"
      )

    igniter = project(mix, %{}) |> install()

    assert content(igniter, "mix.exs") =~
             "compilers: [:arc_analyzer] ++ Mix.compilers() ++ [:arc]"
  end

  test "updates every app of an umbrella" do
    root =
      "defmodule Root.MixProject do\n  use Mix.Project\n  def project, do: [apps_path: \"apps\"]\nend\n"

    igniter =
      project(root, %{
        "apps/a/mix.exs" => String.replace(@project, "MyApp", "A"),
        "apps/b/mix.exs" => String.replace(@project, "MyApp", "B")
      })
      |> install()

    for app <- ["a", "b"] do
      assert content(igniter, "apps/#{app}/mix.exs") =~
               "compilers: [:arc_analyzer] ++ Mix.compilers()"
    end

    refute content(igniter, "mix.exs") =~ "arc_analyzer"
  end
end
