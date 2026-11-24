# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Mix.Tasks.Compile.ArcEventModel do
  @moduledoc """
  Embeds the application's event model in `priv/cratis/event_model` after each compile. Opt in by
  adding the compiler and naming the Arc application:

      def project do
        [
          # ...
          compilers: Mix.compilers() ++ [:arc_event_model],
          arc: [application: MyApp.Arc]
        ]
      end

  Without `arc: [application: ...]` the compiler does nothing. See `Arc.EventModel`.
  """

  use Mix.Task.Compiler

  @recursive false

  @impl Mix.Task.Compiler
  def run(_args) do
    project = Mix.Project.config()[:arc] || []

    case project[:application] do
      nil ->
        {:noop, []}

      application ->
        Mix.Task.run("loadpaths")
        Code.ensure_loaded(application)

        try do
          {:ok, %{written: written}} =
            Arc.EventModel.generate(application, Keyword.take(project, [:output]))

          if written == [], do: {:noop, []}, else: {:ok, []}
        rescue
          error ->
            {:error,
             [
               %Mix.Task.Compiler.Diagnostic{
                 compiler_name: "arc_event_model",
                 file: "mix.exs",
                 message: "Could not build the event model: " <> Exception.message(error),
                 position: 0,
                 severity: :error
               }
             ]}
        end
    end
  end

  @impl Mix.Task.Compiler
  def clean, do: :ok
end
