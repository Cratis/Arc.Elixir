# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Schema do
  @moduledoc """
  Declares the fields of a command, a parameter object or a nested type.

      defmodule MyApp.Authors.Address do
        use Arc.Schema

        schema do
          field :street, :string, required: true
          field :city, :string
        end
      end

  `schema` defines the struct and records typed metadata that Arc uses to bind requests,
  validate input and generate TypeScript.

  ## Field options

    * `:required` - the value must be present (client rule `notEmpty`)
    * `:nullable` - the value may be `nil`; defaults to `true` unless `:required`
    * `:key` - this field identifies the command's event source
    * `:default` - the struct default
    * `:doc` - documentation, written into the generated proxy
    * `:min_length`, `:max_length`, `:email`, `:matches` (a regex source string),
      `:min`, `:max`, `:greater_than`, `:less_than` - declarative rules, evaluated on the server
      and written into the generated validators
  """

  defmodule Field do
    @moduledoc "Typed metadata for one declared field."
    defstruct [
      :name,
      :type,
      :doc,
      nullable?: false,
      required?: false,
      key?: false,
      default: nil,
      rules_source: []
    ]

    @type t :: %__MODULE__{
            name: atom(),
            type: Arc.Types.t(),
            doc: String.t() | nil,
            nullable?: boolean(),
            required?: boolean(),
            key?: boolean(),
            default: term(),
            rules_source: keyword()
          }
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Arc.Schema, only: [schema: 1, field: 2, field: 3]
      Module.register_attribute(__MODULE__, :arc_fields, accumulate: true)
      @before_compile Arc.Schema
    end
  end

  @doc """
  Groups `field/3` declarations and defines the struct, so `%__MODULE__{}` can be used in the
  functions that follow.
  """
  defmacro schema(do: block) do
    struct_fields = block |> statements() |> Enum.map(&struct_field/1)

    quote do
      unquote(block)
      @arc_schema_defined true
      defstruct unquote(struct_fields)
    end
  end

  defp statements({:__block__, _, calls}), do: calls
  defp statements(nil), do: []
  defp statements(call), do: [call]

  defp struct_field({:field, _, [name, _type | rest]}) when is_atom(name) do
    opts = List.first(rest) || []
    default = if Keyword.keyword?(opts), do: Keyword.get(opts, :default), else: nil
    {name, default}
  end

  defp struct_field(other) do
    raise ArgumentError,
          "schema accepts only field declarations with a literal name, got: #{Macro.to_string(other)}"
  end

  @doc "Declares one field. See the module documentation for options."
  defmacro field(name, type, opts \\ []) do
    quote do
      @arc_fields {unquote(name), unquote(type), unquote(opts)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    fields = fields_of(env.module)

    empty_struct =
      if Module.get_attribute(env.module, :arc_schema_defined),
        do: nil,
        else: quote(do: defstruct([]))

    quote do
      unquote(empty_struct)
      def __arc_schema__, do: unquote(Macro.escape(fields))
    end
  end

  @doc false
  @spec fields_of(module()) :: [Field.t()]
  def fields_of(module) do
    module
    |> Module.get_attribute(:arc_fields)
    |> Enum.reverse()
    |> Enum.map(&build_field/1)
  end

  defp build_field({name, type, opts}) do
    required? = Keyword.get(opts, :required, false)

    %Field{
      name: name,
      type: type,
      doc: Keyword.get(opts, :doc),
      required?: required?,
      nullable?: Keyword.get(opts, :nullable, not required?),
      key?: Keyword.get(opts, :key, false),
      default: Keyword.get(opts, :default),
      rules_source: opts
    }
  end

  @doc """
  The fields of any struct module: declared fields for an Arc schema, otherwise inferred from the
  struct's defaults (for example a Chronicle read model). An `nil` default is inferred as a string,
  matching how Chronicle registers it.
  """
  @spec model_fields(module()) :: [Field.t()]
  def model_fields(module) do
    Code.ensure_loaded?(module)

    if function_exported?(module, :__arc_schema__, 0) do
      module.__arc_schema__()
    else
      declared = declared_types(module)

      module
      |> struct()
      |> Map.from_struct()
      |> Enum.sort_by(fn {name, _} -> Atom.to_string(name) end)
      |> Enum.map(fn {name, default} ->
        %Field{
          name: name,
          type: Keyword.get(declared, name, infer_type(default)),
          nullable?: is_nil(default),
          default: default
        }
      end)
    end
  end

  # A model can declare its own field types (a persistence package does, for the types its
  # documents are stored as), so a struct says it once and every reader of it agrees.
  defp declared_types(module) do
    if function_exported?(module, :__arc_types__, 0), do: module.__arc_types__(), else: []
  end

  defp infer_type(%{__struct__: module}) when module in [Date], do: :date
  defp infer_type(%{__struct__: module}) when module in [DateTime, NaiveDateTime], do: :datetime
  defp infer_type(%{__struct__: module}), do: module
  defp infer_type(v) when is_integer(v), do: :integer
  defp infer_type(v) when is_float(v), do: :float
  defp infer_type(v) when is_boolean(v), do: :boolean
  defp infer_type([]), do: {:list, :string}
  defp infer_type([head | _]), do: {:list, infer_type(head)}
  defp infer_type(v) when is_map(v), do: :map
  defp infer_type(_), do: :string

  @doc """
  Binds a wire map (string keys, `camelCase`) to the struct of `module`.

  Returns `{:ok, struct}` or `{:error, results}` where each result has reason `"malformedRequest"`.
  Unknown fields are ignored.
  """
  @spec cast(module(), map()) :: {:ok, struct()} | {:error, [Arc.ValidationResult.t()]}
  def cast(module, wire) when is_map(wire) do
    {values, errors} =
      Enum.reduce(module.__arc_schema__(), {%{}, []}, fn field, {values, errors} ->
        key = Arc.Naming.camel(field.name)

        case Map.fetch(wire, key) do
          :error ->
            {values, errors}

          {:ok, raw} ->
            case Arc.Types.cast(field.type, raw) do
              {:ok, value} ->
                {Map.put(values, field.name, value), errors}

              :error ->
                {values, [malformed(field) | errors]}
            end
        end
      end)

    if errors == [], do: {:ok, struct(module, values)}, else: {:error, Enum.reverse(errors)}
  end

  defp malformed(field) do
    Arc.Validation.error(
      "'#{Arc.Naming.camel(field.name)}' is not a valid #{Arc.Types.describe(field.type)}.",
      [field.name],
      reason: "malformedRequest"
    )
  end
end
