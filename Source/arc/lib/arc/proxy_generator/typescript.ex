# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.ProxyGenerator.TypeScript do
  @moduledoc false

  # Maps Arc field types to TypeScript types, descriptor constructors and imports, and resolves
  # the file each generated artifact lives in.

  alias Arc.Schema

  @fundamentals "@cratis/fundamentals"

  defstruct [:type, :ctor, :import, enumerable?: false]

  @type t :: %__MODULE__{}

  @doc "The TypeScript mapping of a field type."
  @spec map(Arc.Types.t(), integer()) :: t()
  def map({:list, {:list, _}}, _skip),
    do: raise(ArgumentError, "Nested lists are not supported by proxy generation.")

  def map({:list, inner}, skip), do: %{map(inner, skip) | enumerable?: true}
  def map(:string, _), do: %__MODULE__{type: "string", ctor: "String"}
  def map(:integer, _), do: %__MODULE__{type: "number", ctor: "Number"}
  def map(:float, _), do: %__MODULE__{type: "number", ctor: "Number"}
  def map(:boolean, _), do: %__MODULE__{type: "boolean", ctor: "Boolean"}
  def map(:map, _), do: %__MODULE__{type: "object", ctor: "Object"}
  def map(:datetime, _), do: %__MODULE__{type: "Date", ctor: "Date"}
  def map(:uuid, _), do: %__MODULE__{type: "Guid", ctor: "Guid", import: {"Guid", @fundamentals}}

  def map(:date, _),
    do: %__MODULE__{type: "DateOnly", ctor: "DateOnly", import: {"DateOnly", @fundamentals}}

  def map(module, skip) when is_atom(module) do
    if Arc.Types.concept?(module) do
      map(Arc.Types.concept_primitive(module), skip)
    else
      {_ns, name} = Arc.Naming.module_parts(module)
      %__MODULE__{type: name, ctor: name, import: {name, {:module, module}}}
    end
  end

  @doc "The folder, relative to the output directory, an artifact module is generated into."
  @spec folder(module(), integer()) :: String.t()
  def folder(module, skip) do
    {namespace, _} = Arc.Naming.module_parts(module)
    namespace |> Enum.drop(skip) |> Enum.join("/")
  end

  @doc "The import path of generated module `target` as seen from the folder `from`."
  @spec import_path(String.t(), module(), integer()) :: String.t()
  def import_path(from_folder, target, skip) do
    {_ns, name} = Arc.Naming.module_parts(target)
    target_folder = folder(target, skip)
    from = String.split(from_folder, "/", trim: true)
    to = String.split(target_folder, "/", trim: true)
    common = common_prefix(from, to)
    ups = List.duplicate("..", length(from) - length(common))
    downs = Enum.drop(to, length(common))

    case ups ++ downs ++ [name] do
      [first | _] = parts when first == ".." -> Enum.join(parts, "/")
      parts -> "./" <> Enum.join(parts, "/")
    end
  end

  defp common_prefix([a | at], [a | bt]), do: [a | common_prefix(at, bt)]
  defp common_prefix(_, _), do: []

  @doc "Resolves the import statements for a set of mappings, as sorted `{type, module_path}` pairs."
  @spec imports([t()], String.t(), integer()) :: [{String.t(), String.t()}]
  def imports(mappings, from_folder, skip) do
    mappings
    |> Enum.map(& &1.import)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn
      {name, {:module, module}} -> {name, import_path(from_folder, module, skip)}
      {name, package} -> {name, package}
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Every non-concept, non-primitive module reachable from the given field types, so a proxy is
  generated for each nested type and each read model.
  """
  @spec reachable_types([Arc.Types.t()], %{optional(module()) => keyword()}) :: [module()]
  def reachable_types(types, overrides \\ %{}),
    do: collect(types, overrides, MapSet.new()) |> MapSet.to_list() |> Enum.sort()

  defp collect([], _o, seen), do: seen

  defp collect([type | rest], overrides, seen) do
    seen =
      case base(type) do
        module when is_atom(module) ->
          if Arc.Types.primitive?(module) or Arc.Types.concept?(module) or
               MapSet.member?(seen, module) do
            seen
          else
            seen = MapSet.put(seen, module)
            fields = Schema.model_fields(module)
            collect(Enum.map(fields, & &1.type), overrides, seen)
          end
      end

    collect(rest, overrides, seen)
  end

  defp base({:list, inner}), do: base(inner)
  defp base(type), do: type

  @doc "Applies a model's `types:` overrides to its fields."
  @spec model_fields(module(), keyword() | nil) :: [Schema.Field.t()]
  def model_fields(module, overrides) do
    fields = Schema.model_fields(module)

    Enum.map(fields, fn field ->
      case Keyword.fetch(overrides || [], field.name) do
        {:ok, type} -> %{field | type: type}
        :error -> field
      end
    end)
  end
end
