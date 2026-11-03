# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Types do
  @moduledoc """
  The field types Arc understands, and conversion between wire values and Elixir values.

  A type is one of `:string`, `:integer`, `:float`, `:boolean`, `:uuid`, `:date`, `:datetime`,
  `:map`, `{:list, type}`, a `Chronicle.Concept` module (a strongly typed wrapper over one
  primitive), or a module that `use Arc.Schema` (a nested type).
  """

  @primitives [:string, :integer, :float, :boolean, :uuid, :date, :datetime, :map]
  @uuid ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

  @type t :: atom() | {:list, t()}

  @doc "Whether `type` is one of the built-in primitive types."
  @spec primitive?(term()) :: boolean()
  def primitive?(type), do: type in @primitives

  @doc "Whether `module` is a `Chronicle.Concept`."
  @spec concept?(term()) :: boolean()
  def concept?(module) when is_atom(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__chronicle_concept__, 1)

  def concept?(_), do: false

  @doc "Whether `module` is an Arc schema (declares fields with `schema do ... end`)."
  @spec schema?(term()) :: boolean()
  def schema?(module) when is_atom(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__arc_schema__, 0)

  def schema?(_), do: false

  @doc """
  Resolves a concept to the primitive it wraps (`:string`, `:integer`, `:float`, `:boolean` or `:uuid`).
  """
  @spec concept_primitive(module()) :: atom()
  def concept_primitive(module), do: module.__chronicle_concept__(:type)

  @doc """
  Converts a wire value to the Elixir value of `type`.

  Strings are accepted for numbers and booleans so the same function converts query-string
  arguments. Returns `{:ok, value}` or `:error`.
  """
  @spec cast(t(), term()) :: {:ok, term()} | :error
  def cast(_type, nil), do: {:ok, nil}
  def cast(:string, v) when is_binary(v), do: {:ok, v}
  def cast(:integer, v) when is_integer(v), do: {:ok, v}

  def cast(:integer, v) when is_binary(v) do
    case Integer.parse(v) do
      {i, ""} -> {:ok, i}
      _ -> :error
    end
  end

  def cast(:float, v) when is_float(v), do: {:ok, v}
  def cast(:float, v) when is_integer(v), do: {:ok, v * 1.0}

  def cast(:float, v) when is_binary(v) do
    case Float.parse(v) do
      {f, ""} -> {:ok, f}
      _ -> :error
    end
  end

  def cast(:boolean, v) when is_boolean(v), do: {:ok, v}
  def cast(:boolean, "true"), do: {:ok, true}
  def cast(:boolean, "false"), do: {:ok, false}

  def cast(:uuid, v) when is_binary(v) do
    if Regex.match?(@uuid, v), do: {:ok, String.downcase(v)}, else: :error
  end

  def cast(:date, %Date{} = v), do: {:ok, v}

  def cast(:date, v) when is_binary(v) do
    case Date.from_iso8601(v) do
      {:ok, date} -> {:ok, date}
      _ -> :error
    end
  end

  def cast(:datetime, %DateTime{} = v), do: {:ok, v}

  def cast(:datetime, v) when is_binary(v) do
    case DateTime.from_iso8601(v) do
      {:ok, dt, _offset} -> {:ok, dt}
      _ -> :error
    end
  end

  def cast(:map, v) when is_map(v), do: {:ok, v}

  def cast({:list, inner}, v) when is_list(v) do
    Enum.reduce_while(v, {:ok, []}, fn item, {:ok, acc} ->
      case cast(inner, item) do
        {:ok, casted} -> {:cont, {:ok, [casted | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      :error -> :error
    end
  end

  def cast(module, v) when is_atom(module) do
    cond do
      concept?(module) ->
        with {:ok, inner} <- cast(concept_primitive(module), v),
             do: {:ok, struct(module, value: inner)}

      schema?(module) and is_map(v) ->
        case Arc.Schema.cast(module, v) do
          {:ok, struct} -> {:ok, struct}
          {:error, _} -> :error
        end

      true ->
        :error
    end
  end

  def cast(_type, _value), do: :error

  @doc "A human-readable name for a type, used in validation messages."
  @spec describe(t()) :: String.t()
  def describe({:list, inner}), do: "list of #{describe(inner)}"
  def describe(type) when type in @primitives, do: Atom.to_string(type)
  def describe(module) when is_atom(module), do: inspect(module)
end
