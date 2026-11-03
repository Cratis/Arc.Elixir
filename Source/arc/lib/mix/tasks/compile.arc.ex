# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Mix.Tasks.Compile.Arc do
  @moduledoc """
  Regenerates TypeScript proxies after each compile. Opt in by adding the compiler:

      def project do
        [
          # ...
          compilers: Mix.compilers() ++ [:arc],
          arc: [application: MyApp.Arc, output: "assets/src/arc"]
        ]
      end

  Without `arc: [application: ..., output: ...]` the compiler does nothing, so adding it to a
  project that does not use React is harmless. Under `mix phx.server`, Phoenix's code reloader
  runs the project's compilers, so proxies follow your edits.
  """

  use Mix.Task.Compiler

  @recursive false

  @impl Mix.Task.Compiler
  def run(_args) do
    project = Mix.Project.config()[:arc] || []

    with application when not is_nil(application) <- project[:application],
         output when not is_nil(output) <- project[:output] do
      Mix.Task.run("loadpaths")

      case Arc.ProxyGenerator.generate(application,
             output: output,
             remove_stale: Keyword.get(project, :remove_stale, true)
           ) do
        {:ok, %{written: [], removed: []}} -> {:noop, []}
        {:ok, _result} -> {:ok, []}
        {:error, messages} -> {:error, Enum.map(messages, &diagnostic/1)}
      end
    else
      _ -> {:noop, []}
    end
  end

  defp diagnostic(message) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "arc",
      file: "mix.exs",
      message: message,
      position: 0,
      severity: :error
    }
  end

  @impl Mix.Task.Compiler
  def clean, do: :ok
end
