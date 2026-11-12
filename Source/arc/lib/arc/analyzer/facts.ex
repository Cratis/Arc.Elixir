# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Facts do
  @moduledoc false
  # Where the tracer writes while the Elixir compiler runs, and the manifest that carries the
  # facts from one compile to the next.
  #
  # The Elixir compiler is incremental: on a second `mix compile` it recompiles only the files
  # that changed, so the tracer only sees those. The facts of every other file come from the
  # manifest. A recompiled file's old facts are replaced wholesale (a module deleted from it
  # must not linger), and the facts of a file that no longer exists are dropped.

  @table :arc_analyzer_facts
  @manifest "compile.arc_analyzer"
  @format 1

  @type per_file :: %{String.t() => %{modules: [map()], calls: [map()]}}

  @doc "Creates the collection table. The calling process owns it."
  @spec start() :: :ok
  def start do
    stop()
    :ets.new(@table, [:bag, :public, :named_table, write_concurrency: true])
    :ok
  end

  @doc "Deletes the collection table."
  @spec stop() :: :ok
  def stop do
    if active?(), do: :ets.delete(@table)
    :ok
  end

  @doc "Whether a collection is running. The tracer does nothing when it is not."
  @spec active?() :: boolean()
  def active?, do: :ets.whereis(@table) != :undefined

  @doc "Records a fact for a module."
  @spec record(module(), :module | :call, map()) :: true
  def record(module, tag, fact), do: :ets.insert(@table, {module, {tag, fact}})

  @doc "Everything collected during this compile, grouped by source file."
  @spec collected() :: per_file()
  def collected do
    @table
    |> :ets.tab2list()
    |> Enum.reduce(%{}, fn {_module, {tag, fact}}, acc ->
      key = if tag == :module, do: :modules, else: :calls

      Map.update(
        acc,
        fact.file,
        Map.put(%{modules: [], calls: []}, key, [fact]),
        &Map.update!(&1, key, fn facts -> [fact | facts] end)
      )
    end)
  end

  @doc """
  Merges this compile's facts over the previous ones.

  Files compiled this time replace their previous entry; files that no longer exist are
  dropped.
  """
  @spec merge(per_file(), per_file()) :: per_file()
  def merge(previous, current) do
    previous
    |> Map.drop(Map.keys(current))
    |> Enum.filter(fn {file, _} -> File.exists?(file) end)
    |> Map.new()
    |> Map.merge(current)
  end

  @doc "Flattens per-file facts into the struct rules receive."
  @spec to_project(per_file()) :: Arc.Analyzer.Project.t()
  def to_project(per_file) do
    facts = Map.values(per_file)

    %Arc.Analyzer.Project{
      modules: facts |> Enum.flat_map(& &1.modules) |> Map.new(&{&1.module, &1}),
      calls: facts |> Enum.flat_map(& &1.calls) |> Enum.sort_by(&{&1.file, &1.line}),
      config: Arc.Analyzer.Config.load()
    }
  end

  @doc "Reads the manifest, or `nil` when there is none or it was written by another version."
  @spec read_manifest(String.t()) :: per_file() | nil
  def read_manifest(path \\ manifest_path()) do
    with {:ok, binary} <- File.read(path),
         {:ok, {@format, version, per_file}} <- safe_decode(binary),
         true <- version == analyzer_version() do
      per_file
    else
      _ -> nil
    end
  end

  @doc "Writes the manifest."
  @spec write_manifest(per_file(), String.t()) :: :ok
  def write_manifest(per_file, path \\ manifest_path()) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary({@format, analyzer_version(), per_file}))
  end

  @doc "Where the manifest lives for the project being compiled."
  @spec manifest_path() :: String.t()
  def manifest_path, do: Path.join(Mix.Project.manifest_path(), @manifest)

  # The manifest holds facts, not results, so it stays valid across rule changes. It is
  # invalidated when the fact shape changes, which is what the version of this library tracks.
  defp analyzer_version do
    case Application.spec(:cratis_arc, :vsn) do
      nil -> "unknown"
      vsn -> List.to_string(vsn)
    end
  end

  defp safe_decode(binary) do
    {:ok, :erlang.binary_to_term(binary)}
  rescue
    ArgumentError -> :error
  end
end
