# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.CratisArc.Install do
    @shortdoc "Adds the Arc analyzer compiler to mix.exs"

    @moduledoc """
    Turns on the Arc analyzer by adding `:arc_analyzer` ahead of the default compilers:

        compilers: [:arc_analyzer] ++ Mix.compilers()

    Run it with `mix igniter.install cratis_arc`, which also adds the dependency, or on its
    own with `mix cratis_arc.install` once `cratis_arc` is a dependency.

    Running it again changes nothing. A `compilers:` list that already has the analyzer is left
    as it is, and one that has other compilers keeps them: `Mix.compilers() ++ [:arc]` becomes
    `[:arc_analyzer] ++ Mix.compilers() ++ [:arc]`.

    In an umbrella project it updates the `mix.exs` of every app in `apps/`.
    """

    use Igniter.Mix.Task

    alias Igniter.Code.{Function, Keyword}

    @compiler :arc_analyzer

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{group: :cratis_arc, example: "mix cratis_arc.install"}
    end

    @impl Igniter.Mix.Task
    def supports_umbrella?, do: true

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter = Igniter.include_glob(igniter, "apps/*/mix.exs")

      igniter
      |> mix_files()
      |> Enum.reduce(igniter, fn path, igniter ->
        Igniter.update_elixir_file(igniter, path, &add_compiler/1)
      end)
    end

    defp mix_files(igniter) do
      children =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&Rewrite.Source.get(&1, :path))
        |> Enum.filter(&Regex.match?(~r{^apps/[^/]+/mix\.exs$}, &1))
        |> Enum.sort()

      if children == [], do: ["mix.exs"], else: children
    end

    defp add_compiler(zipper) do
      with {:ok, zipper} <- Function.move_to_def(zipper, :project, 0),
           zipper <- Igniter.Code.Common.maybe_move_to_single_child_block(zipper) do
        value = Sourceror.parse_string!("[#{inspect(@compiler)}] ++ Mix.compilers()")

        case Keyword.put_in_keyword(zipper, [:compilers], value, &prepend/1) do
          {:ok, zipper} -> {:ok, zipper}
          _ -> {:warning, manual_instructions()}
        end
      else
        _ -> {:warning, manual_instructions()}
      end
    end

    defp prepend(zipper) do
      current = Sourceror.to_string(zipper.node)

      if String.contains?(current, inspect(@compiler)) do
        {:ok, zipper}
      else
        {:ok, Igniter.Code.Common.replace_code(zipper, "[#{inspect(@compiler)}] ++ #{current}")}
      end
    end

    defp manual_instructions do
      "Could not update `compilers` in mix.exs. Add it yourself: " <>
        "`compilers: [#{inspect(@compiler)}] ++ Mix.compilers()`"
    end
  end
else
  defmodule Mix.Tasks.CratisArc.Install do
    @shortdoc "Adds the Arc analyzer compiler to mix.exs (needs Igniter)"

    @moduledoc """
    Needs Igniter. Install it, or add the compiler yourself:

        compilers: [:arc_analyzer] ++ Mix.compilers()
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      `mix cratis_arc.install` needs Igniter. Add `{:igniter, "~> 0.6", only: :dev}` to your
      dependencies, or add the compiler to mix.exs yourself:

          compilers: [:arc_analyzer] ++ Mix.compilers()
      """)

      exit({:shutdown, 1})
    end
  end
end
