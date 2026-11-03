# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Mix.Tasks.Arc.Gen.Proxies do
  @moduledoc """
  Generates TypeScript proxies for the React frontend. Proxy generation is opt-in.

      mix arc.gen.proxies
      mix arc.gen.proxies --application MyApp.Arc --output assets/src/arc
      mix arc.gen.proxies --check

  ## Options

    * `--application` - the `Arc.Application` module; defaults to `arc: [application: ...]` in `mix.exs`
    * `--output` - the output directory; defaults to `arc: [output: ...]` in `mix.exs`
    * `--check` - write nothing; exit with an error when the proxies on disk are out of date.
      Use it in CI to keep committed proxies current.
    * `--no-remove-stale` - keep generated files of artifacts that no longer exist

  See `Arc.ProxyGenerator`.
  """

  use Mix.Task

  @shortdoc "Generates TypeScript proxies for commands and queries"
  @requirements ["app.config"]

  @switches [application: :string, output: :string, check: :boolean, remove_stale: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: @switches)
    project = Mix.Project.config()[:arc] || []

    application =
      (opts[:application] && Module.concat([opts[:application]])) || project[:application]

    output = opts[:output] || project[:output]

    cond do
      is_nil(application) ->
        Mix.raise(
          "No Arc application. Pass --application MyApp.Arc or set arc: [application: MyApp.Arc] in mix.exs."
        )

      is_nil(output) ->
        Mix.raise("No output directory. Pass --output DIR or set arc: [output: DIR] in mix.exs.")

      true ->
        Mix.Task.run("compile")
        generate(application, output, opts)
    end
  end

  defp generate(application, output, opts) do
    check? = Keyword.get(opts, :check, false)

    case Arc.ProxyGenerator.generate(application,
           output: output,
           dry_run: check?,
           remove_stale: Keyword.get(opts, :remove_stale, true)
         ) do
      {:ok, %{written: [], removed: []} = result} ->
        Mix.shell().info("Proxies are up to date (#{length(result.unchanged)} files).")

      {:ok, result} when check? ->
        Mix.raise(
          "Proxies are out of date: #{length(result.written)} to write, #{length(result.removed)} to remove. Run mix arc.gen.proxies."
        )

      {:ok, result} ->
        Mix.shell().info(
          "Generated proxies: #{length(result.written)} written, #{length(result.unchanged)} unchanged, #{length(result.removed)} removed."
        )

      {:error, messages} ->
        Mix.raise(Enum.join(messages, "\n"))
    end
  end
end
