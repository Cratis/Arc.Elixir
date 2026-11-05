# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.NamingPolicy do
  @moduledoc """
  How documents and collections are named.

  A naming policy turns the name of a struct field into the name of a document member, and a
  document module into the name of its collection. Configure it once, before writing data: changing
  it does not rename existing members or collections.

      config :my_app, MyApp.Arc,
        mongodb: [naming_policy: :camel_case]

  The built-in policies are

    * `:none` (default) - names exactly as defined: field `display_name` is stored as
      `"display_name"` and `MyApp.Books.Book` lives in the collection `"Book"`
    * `:camel_case` - `"displayName"` and `"book"`, matching the names of the wire format
    * `:snake_case` - `"display_name"` and `"book"`

  or a module implementing this behaviour. The `id` field is always stored as `_id`.
  """

  @doc "The name of a document member for a struct field."
  @callback property_name(field :: String.t()) :: String.t()

  @doc "The name of the collection for a document module."
  @callback collection_name(document :: module()) :: String.t()

  @doc false
  @spec resolve(atom() | module()) :: module()
  def resolve(:none), do: Arc.MongoDB.NamingPolicy.None
  def resolve(:camel_case), do: Arc.MongoDB.NamingPolicy.CamelCase
  def resolve(:snake_case), do: Arc.MongoDB.NamingPolicy.SnakeCase
  def resolve(nil), do: Arc.MongoDB.NamingPolicy.None
  def resolve(module) when is_atom(module), do: module

  @doc false
  @spec type_name(module()) :: String.t()
  def type_name(module), do: module |> Module.split() |> List.last()
end

defmodule Arc.MongoDB.NamingPolicy.None do
  @moduledoc "Names exactly as defined."
  @behaviour Arc.MongoDB.NamingPolicy

  @impl true
  def property_name(name), do: name

  @impl true
  def collection_name(module), do: Arc.MongoDB.NamingPolicy.type_name(module)
end

defmodule Arc.MongoDB.NamingPolicy.CamelCase do
  @moduledoc "`camelCase` members and collections."
  @behaviour Arc.MongoDB.NamingPolicy

  @impl true
  def property_name(name), do: Arc.Naming.camel(name)

  @impl true
  def collection_name(module) do
    {first, rest} = module |> Arc.MongoDB.NamingPolicy.type_name() |> String.split_at(1)
    String.downcase(first) <> rest
  end
end

defmodule Arc.MongoDB.NamingPolicy.SnakeCase do
  @moduledoc "`snake_case` members and collections."
  @behaviour Arc.MongoDB.NamingPolicy

  @impl true
  def property_name(name), do: Macro.underscore(name)

  @impl true
  def collection_name(module),
    do: module |> Arc.MongoDB.NamingPolicy.type_name() |> Macro.underscore()
end
