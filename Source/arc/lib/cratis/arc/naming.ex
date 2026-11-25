# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Naming do
  @moduledoc """
  Name conversions shared by routing, the wire format and proxy generation.

  Elixir names are `snake_case`; the Arc wire format and the generated TypeScript use
  `camelCase`; conventional routes use lowercase `kebab-case`.
  """

  @doc """
  Converts a `snake_case` name or atom to `camelCase`.

      iex> Cratis.Arc.Naming.camel(:first_name)
      "firstName"
  """
  @spec camel(atom() | String.t()) :: String.t()
  def camel(name) when is_atom(name), do: name |> Atom.to_string() |> camel()

  def camel(name) when is_binary(name) do
    case String.split(name, "_", trim: true) do
      [] -> ""
      [first | rest] -> first <> Enum.map_join(rest, &String.capitalize/1)
    end
  end

  @doc """
  Converts a `PascalCase` or `camelCase` name to `kebab-case`.

      iex> Cratis.Arc.Naming.kebab("RegisterAuthor")
      "register-author"
  """
  @spec kebab(atom() | String.t()) :: String.t()
  def kebab(name) when is_atom(name), do: name |> Atom.to_string() |> kebab()

  def kebab(name) when is_binary(name) do
    name
    |> String.replace("_", "-")
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1-\\2")
    |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1-\\2")
    |> String.downcase()
  end

  @doc """
  Converts a `snake_case` function name to `PascalCase`, for query proxy class names.

      iex> Cratis.Arc.Naming.pascal(:all_authors)
      "AllAuthors"
  """
  @spec pascal(atom() | String.t()) :: String.t()
  def pascal(name) when is_atom(name), do: name |> Atom.to_string() |> pascal()

  def pascal(name) when is_binary(name) do
    name |> String.split(["_", "-"], trim: true) |> Enum.map_join(&capitalize_first/1)
  end

  @typedoc """
  How the declared name (the `id:` of a command, event type, read model or reactor) is shown by the
  structure and the event model: `:pascal_case` (default, `"register-author"` is `"RegisterAuthor"`),
  `:kebab_case`, `:as_declared`, or a function taking the declared name.
  """
  @type display_style :: :pascal_case | :kebab_case | :as_declared | (String.t() -> String.t())

  @doc """
  The name to show for a declared `id`, in the configured style (`:display_names` of the Arc
  application).

      iex> Cratis.Arc.Naming.display("register-author", :pascal_case)
      "RegisterAuthor"
      iex> Cratis.Arc.Naming.display("register-author", :kebab_case)
      "register-author"
  """
  @spec display(String.t(), display_style()) :: String.t()
  def display(id, style \\ :pascal_case)
  def display(id, :pascal_case), do: pascal(id)
  def display(id, :kebab_case), do: kebab(id)
  def display(id, :as_declared), do: id
  def display(id, style) when is_function(style, 1), do: style.(id)

  @doc """
  Splits a module into its namespace segments and its name.

      iex> Cratis.Arc.Naming.module_parts(MyApp.Authors.Registration.RegisterAuthor)
      {["MyApp", "Authors", "Registration"], "RegisterAuthor"}
  """
  @spec module_parts(module()) :: {[String.t()], String.t()}
  def module_parts(module) do
    parts = module |> Module.split()
    {Enum.drop(parts, -1), List.last(parts)}
  end

  defp capitalize_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp capitalize_first(""), do: ""
end
