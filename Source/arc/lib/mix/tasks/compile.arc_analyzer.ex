# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Mix.Tasks.Compile.ArcAnalyzer do
  @moduledoc """
  Checks your code against the Arc analyzer rules while it compiles.

  Add the compiler ahead of the default compilers, or run `mix cratis_arc.install`:

      def project do
        [
          # ...
          compilers: [:arc_analyzer] ++ Mix.compilers()
        ]
      end

  It registers `Arc.Analyzer` as a compiler tracer, lets the Elixir compiler run, and then runs
  the rules over what the tracer saw plus the manifest of earlier builds. Findings are reported
  as Mix diagnostics, so editors that run `mix compile` show them. `--warnings-as-errors` turns
  warnings into a failed build.

  See `Arc.Analyzer` for how it works and `Arc.Analyzer.Config` for the options.
  """

  use Mix.Task.Compiler

  alias Arc.Analyzer.{Config, Facts, Runner}
  alias Mix.Task.Compiler.Diagnostic

  @recursive true

  @impl Mix.Task.Compiler
  def run(args) do
    config = Config.load()

    if config.enabled do
      Facts.start()
      register_tracer()

      Mix.Task.Compiler.after_compiler(:elixir, fn result ->
        after_elixir(result, config, "--warnings-as-errors" in args)
      end)
    end

    {:noop, []}
  end

  @impl Mix.Task.Compiler
  def manifests, do: [Facts.manifest_path()]

  @impl Mix.Task.Compiler
  def clean do
    File.rm(Facts.manifest_path())
    :ok
  end

  defp register_tracer do
    tracers = Code.get_compiler_option(:tracers) |> List.delete(Arc.Analyzer)
    Code.put_compiler_option(:tracers, [Arc.Analyzer | tracers])
  end

  defp after_elixir({status, diagnostics}, config, warnings_as_errors?) do
    collected = Facts.collected()
    Facts.stop()
    unregister_tracer()

    if status == :error do
      {status, diagnostics}
    else
      per_file = Facts.merge(Facts.read_manifest() || %{}, collected)
      Facts.write_manifest(per_file)

      findings =
        config_problems(config) ++
          Runner.run(Facts.to_project(per_file) |> Map.put(:config, config), config)

      Enum.each(findings, &print/1)
      {final_status(status, findings, warnings_as_errors?), diagnostics ++ findings}
    end
  end

  defp unregister_tracer do
    Code.put_compiler_option(
      :tracers,
      List.delete(Code.get_compiler_option(:tracers), Arc.Analyzer)
    )
  end

  defp final_status(status, findings, warnings_as_errors?) do
    failing = if warnings_as_errors?, do: [:error, :warning], else: [:error]
    if Enum.any?(findings, &(&1.severity in failing)), do: :error, else: status
  end

  defp config_problems(config) do
    for problem <- Config.problems(config) do
      %Diagnostic{
        compiler_name: "arc_analyzer",
        file: "config/config.exs",
        position: 0,
        severity: :warning,
        message: problem
      }
    end
  end

  defp print(%Diagnostic{severity: :error} = diagnostic),
    do: Mix.shell().error("error: #{diagnostic.message}\n  #{location(diagnostic)}")

  defp print(%Diagnostic{severity: :information} = diagnostic),
    do: Mix.shell().info("info: #{diagnostic.message}\n  #{location(diagnostic)}")

  defp print(%Diagnostic{} = diagnostic),
    do: IO.warn(diagnostic.message, file: diagnostic.file, line: diagnostic.position)

  defp location(%Diagnostic{file: file, position: line}),
    do: "#{Path.relative_to_cwd(file)}:#{line}"
end
