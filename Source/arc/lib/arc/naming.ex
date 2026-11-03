# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Naming do
  @moduledoc """
  Name conversions shared by routing, the wire format and proxy generation.

  Elixir names are `snake_case`; the Arc wire format and the generated TypeScript use
  `camelCase`; conventional routes use lowercase `kebab-case`.
  """

  @doc """
  Converts a `snake_case` name or atom to `camelCase`.

      iex> Arc.Naming.camel(:first_name)
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

      iex> Arc.Naming.kebab("RegisterAuthor")
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

      iex> Arc.Naming.pascal(:all_authors)
      "AllAuthors"
  """
  @spec pascal(atom() | String.t()) :: String.t()
  def pascal(name) when is_atom(name), do: name |> Atom.to_string() |> pascal()

  def pascal(name) when is_binary(name) do
    name |> String.split("_", trim: true) |> Enum.map_join(&capitalize_first/1)
  end

  @doc """
  Splits a module into its namespace segments and its name.

      iex> Arc.Naming.module_parts(MyApp.Authors.Registration.RegisterAuthor)
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
