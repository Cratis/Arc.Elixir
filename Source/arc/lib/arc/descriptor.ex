# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Descriptor do
  @moduledoc """
  Compile-time metadata of a command or a read model, exposed as `__arc__/0` on the artifact.

  Discovery reads descriptors from compiled modules; there is no runtime reflection over source.
  """

  defmodule Query do
    @moduledoc "Metadata of one query on a read model."
    defstruct [
      :name,
      :doc,
      :params,
      :watch,
      :topics,
      :http_method,
      many?: true,
      observable?: false,
      authorization: %{roles: [], policy: nil, allow_anonymous: false, authenticated?: false}
    ]
  end

  defstruct [
    :kind,
    :module,
    :name,
    :namespace,
    :doc,
    :fields,
    :response,
    :key,
    :model,
    :model_types,
    :queries,
    authorization: %{roles: [], policy: nil, allow_anonymous: false, authenticated?: false}
  ]

  @type t :: %__MODULE__{}

  @doc "The fully qualified name of a query: the container module plus the PascalCase function name."
  @spec query_name(t(), Query.t()) :: String.t()
  def query_name(%__MODULE__{module: module}, %Query{name: name}),
    do: "#{inspect(module)}.#{Arc.Naming.pascal(name)}"

  @doc """
  The conventional route of a command, built from `route_prefix`, the namespace segments after
  `segments_to_skip`, and the kebab-cased command name.
  """
  @spec command_route(t(), keyword()) :: String.t()
  def command_route(%__MODULE__{} = descriptor, opts \\ []),
    do: route(descriptor, descriptor.name, opts)

  @doc "The conventional route of a query."
  @spec query_route(t(), Query.t(), keyword()) :: String.t()
  def query_route(%__MODULE__{} = descriptor, %Query{name: name}, opts \\ []),
    do: route(descriptor, Atom.to_string(name), opts)

  defp route(%__MODULE__{namespace: namespace}, name, opts) do
    prefix = Keyword.get(opts, :route_prefix, "api")
    skip = Keyword.get(opts, :segments_to_skip, 1)

    segments =
      namespace
      |> Enum.drop(skip)
      |> Enum.map(&Arc.Naming.kebab/1)
      |> Kernel.++([Arc.Naming.kebab(name)])

    "/" <> Enum.join([prefix | segments], "/")
  end

  @doc """
  Resolves the module, feature and slice of an artifact from its namespace segments, with the
  same rules the C# generator uses: fewer than three segments fill the deepest parts first.
  """
  @spec slice_location(t(), integer()) :: {String.t(), String.t(), String.t()}
  def slice_location(%__MODULE__{namespace: namespace}, segments_to_skip) do
    case Enum.drop(namespace, segments_to_skip) do
      [] -> {"", "", ""}
      [a] -> {"", "", a}
      [a, b] -> {"", a, b}
      parts -> {hd(parts), parts |> Enum.slice(1..-2//1) |> Enum.join("."), List.last(parts)}
    end
  end
end
