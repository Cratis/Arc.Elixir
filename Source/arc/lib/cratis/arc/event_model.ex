# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.EventModel do
  @moduledoc """
  The event model of an application: its modules, features and slices with their commands, events,
  read models, queries and reactions, drawn by the explorer at `/.cratis/event-model`.

  The model is **generated while you compile** and embedded in the application's `priv` folder, the
  way the C# build embeds it in the assembly, so it is part of every release and nothing is
  analysed at run time. Add the compiler:

      def project do
        [
          # ...
          compilers: Mix.compilers() ++ [:arc_event_model],
          arc: [application: MyApp.Arc]
        ]
      end

  It writes `priv/cratis/event_model/`: a `catalog.json` listing the documents (the application, one
  per module and one per feature), and for each the board model (`*.model.json`, the document
  `@cratis/event-models` reads) and its Screenplay source (`*.screenplay`).

  ## Where the events of a command come from

  A command returns the events it appends, so they are read from the compiled code: the event types
  the module builds. A reactor's emitted events are found the same way, and the events it handles
  come from `@handles`. Reducers and projections list the events they consume.

  ## Serving it

  `Cratis.Arc.Plug` serves the explorer and its API:

  | Route | Answers |
  | --- | --- |
  | `/.cratis/event-model/` | the explorer |
  | `/.cratis/event-model/hierarchy` | the projects and their documents |
  | `/.cratis/event-model/documents/{project}/{document}/model` | the board model |
  | `/.cratis/event-model/documents/{project}/{document}/source` | the Screenplay source |
  | `/.cratis/event-model/assets/*` | the explorer's files |

  Configure it with `event_model:` on the Arc application: `:auto` (the default: served under
  `mix` in development, not in a release), `true` or `false`. The `introspection` option decides
  who may read it. A route that reveals the whole model should not be open in production.
  """

  alias Cratis.Arc.EventModel.{Builder, Documents}

  @dir "cratis/event_model"

  @doc """
  Builds the event model of `application` and writes it under `priv/cratis/event_model` of the
  current Mix project (or `:output`). Returns `{:ok, %{written: [path], project: id, problems:
  [problem]}}`; a problem says where the model is incomplete (`Cratis.Arc.EventModel.Validation`).
  """
  @spec generate(module(), keyword()) ::
          {:ok, %{written: [Path.t()], project: String.t(), problems: [String.t()]}}
  def generate(application, opts \\ []) do
    config = application.config()
    otp_app = Keyword.fetch!(config, :otp_app)
    project_id = to_string(otp_app)
    output = Keyword.get(opts, :output, Path.join("priv", @dir))

    built = Builder.build(application)
    documents = Documents.build(built, project_id)

    File.mkdir_p!(output)
    stale = output |> Path.join("*") |> Path.wildcard()

    files =
      for doc <- documents,
          {suffix, content} <- [
            {".model.json", Jason.encode!(doc.model)},
            {".screenplay", doc.source}
          ] do
        {Path.join(output, slug(doc.id) <> suffix), content}
      end

    catalog = %{
      "project" => %{"id" => project_id, "name" => built.name},
      "documents" =>
        for doc <- documents do
          %{
            "id" => doc.id,
            "title" => doc.title,
            "namespace" => doc.namespace,
            "kind" => Atom.to_string(doc.kind),
            "parentId" => doc.parent_id,
            "resourceName" => slug(doc.id)
          }
        end
    }

    files = [{Path.join(output, "catalog.json"), Jason.encode!(catalog, pretty: true)} | files]
    written = for {path, content} <- files, write_if_changed(path, content), do: path

    Enum.each(stale -- Enum.map(files, &elem(&1, 0)), &File.rm/1)
    {:ok, %{written: written, project: project_id, problems: built.problems}}
  end

  defp write_if_changed(path, content) do
    if File.exists?(path) and File.read!(path) == content do
      false
    else
      File.write!(path, content)
      true
    end
  end

  @doc "The projects embedded in the given OTP applications, as the explorer's hierarchy."
  @spec hierarchy([atom()]) :: [map()]
  def hierarchy(apps) do
    for app <- apps, {:ok, catalog} <- [catalog(app)] do
      %{
        "id" => catalog["project"]["id"],
        "name" => catalog["project"]["name"],
        "documents" => catalog["documents"]
      }
    end
  end

  @doc "A document of a project: `{:ok, content}` of the given kind (`:model` or `:source`)."
  @spec document([atom()], String.t(), String.t(), :model | :source) :: {:ok, binary()} | :error
  def document(apps, project_id, document_id, kind) do
    with app when not is_nil(app) <- Enum.find(apps, &(to_string(&1) == project_id)),
         {:ok, catalog} <- catalog(app),
         %{"resourceName" => resource} <-
           Enum.find(catalog["documents"], &(&1["id"] == document_id)),
         {:ok, dir} <- priv(app) do
      suffix = if kind == :model, do: ".model.json", else: ".screenplay"

      File.read(Path.join(dir, resource <> suffix))
      |> then(fn
        {:ok, c} -> {:ok, c}
        _ -> :error
      end)
    else
      _ -> :error
    end
  end

  defp catalog(app) do
    with {:ok, dir} <- priv(app),
         {:ok, json} <- File.read(Path.join(dir, "catalog.json")),
         {:ok, catalog} <- Jason.decode(json) do
      {:ok, catalog}
    else
      _ -> :error
    end
  end

  # `config :cratis_arc, :event_model_dirs, %{app => dir}` points an application at another folder:
  # a hook for specs and for releases that keep the generated files elsewhere.
  defp priv(app) do
    case Map.get(Application.get_env(:cratis_arc, :event_model_dirs, %{}), app) do
      nil ->
        Application.load(app)

        case :code.priv_dir(app) do
          path when is_list(path) -> {:ok, Path.join(List.to_string(path), @dir)}
          _ -> :error
        end

      dir ->
        {:ok, dir}
    end
  end

  defp slug(id), do: String.replace(id, ~r/[^A-Za-z0-9._-]/, "_")
end
