# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Runner do
  @moduledoc """
  Runs the rules over a project's facts and turns the findings into Mix diagnostics.

  Pure: it reads nothing from disk and prints nothing, which is what lets the rules be
  specified with hand-built facts.
  """

  alias Arc.Analyzer.{Config, Finding, Project, Rule, Rules}
  alias Mix.Task.Compiler.Diagnostic

  @doc """
  Runs `rules` (every shipped rule by default) over `project`.

  Rules configured `:off` do not run. A finding is dropped when its module suppresses the
  rule with `@arc_analyzer ignore: ["ARCE0001"]`.
  """
  @spec run(Project.t(), Config.t(), [module()]) :: [Diagnostic.t()]
  def run(project, config, rules \\ Rules.all())

  def run(%Project{} = project, %Config{enabled: true} = config, rules) do
    rules
    |> Enum.map(&{&1, Config.severity(config, &1)})
    |> Enum.reject(fn {_rule, severity} -> severity == :off end)
    |> Enum.flat_map(fn {rule, severity} ->
      project
      |> findings(rule)
      |> Enum.reject(&suppressed?(&1, rule, project))
      |> Enum.map(&diagnostic(&1, rule, severity))
    end)
    |> Enum.sort_by(&{&1.file, &1.position, &1.message})
  end

  def run(%Project{}, %Config{enabled: false}, _rules), do: []

  defp findings(project, rule) do
    Code.ensure_loaded!(rule)

    calls =
      if function_exported?(rule, :check_call, 2),
        do: Enum.flat_map(project.calls, &rule.check_call(&1, project)),
        else: []

    modules =
      if function_exported?(rule, :check_module, 2),
        do: Enum.flat_map(Map.values(project.modules), &rule.check_module(&1, project)),
        else: []

    whole =
      if function_exported?(rule, :check_project, 1), do: rule.check_project(project), else: []

    calls ++ modules ++ whole
  end

  defp suppressed?(%Finding{module: module}, rule, project) do
    case Project.module_fact(project, module) do
      %{ignore: ignore} -> rule.id() in ignore
      _ -> false
    end
  end

  defp diagnostic(%Finding{} = finding, rule, severity) do
    %Diagnostic{
      compiler_name: "arc_analyzer",
      file: finding.file,
      position: finding.line,
      severity: mix_severity(severity),
      message: "#{rule.id()}: #{finding.message}\n  See #{Rule.documentation_url(rule.id())}",
      details: %{rule: rule.id()}
    }
  end

  defp mix_severity(:info), do: :information
  defp mix_severity(severity), do: severity
end
