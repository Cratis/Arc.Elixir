# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.Codec do
  @moduledoc """
  Converts between structs and BSON documents, and between struct-shaped filters and the names
  and values stored.

  This is the *conventions* part of the package: naming policy, `_id`, UUID representation,
  dates, concepts, nested documents and collections that are never `nil`. See
  `Arc.MongoDB.Document` for the table of representations.
  """

  alias Arc.MongoDB.Document
  alias Arc.Schema

  @type field :: %{name: atom(), key: String.t(), type: Arc.Types.t() | :object_id}

  @doc "The stored fields of a document module, in the order of the struct."
  @spec fields(module(), module()) :: [field()]
  def fields(module, policy) do
    cache = {__MODULE__, module, policy}

    case :persistent_term.get(cache, nil) do
      nil ->
        fields = build_fields(module, policy)
        :persistent_term.put(cache, fields)
        fields

      fields ->
        fields
    end
  end

  defp build_fields(module, policy) do
    options = Document.options(module)

    for field <- Schema.model_fields(module) do
      type = Keyword.get(options.types, field.name, field.type)

      key =
        if field.name == options.id,
          do: "_id",
          else: policy.property_name(Atom.to_string(field.name))

      %{name: field.name, key: key, type: type}
    end
  end

  @doc "The collection name of a document module under a naming policy."
  @spec collection_name(module(), module()) :: String.t()
  def collection_name(module, policy) do
    Document.options(module).collection || policy.collection_name(module)
  end

  @doc "Converts a struct to the document to store."
  @spec to_document(struct(), module()) :: map()
  def to_document(%{__struct__: module} = struct, policy) do
    for %{name: name, key: key, type: type} <- fields(module, policy), into: %{} do
      {key, encode(type, Map.get(struct, name), policy)}
    end
  end

  @doc "Converts a stored document to a struct of `module`."
  @spec from_document(map(), module(), module()) :: struct()
  def from_document(document, module, policy) when is_map(document) do
    template = struct(module)

    values =
      for %{name: name, key: key, type: type} <- fields(module, policy), into: %{} do
        case Map.fetch(document, key) do
          {:ok, value} when not is_nil(value) -> {name, decode(type, value, policy)}
          {:ok, nil} -> {name, Map.get(template, name) |> never_nil(type)}
          :error -> {name, Map.get(template, name) |> never_nil(type)}
        end
      end

    struct(module, values)
  end

  # A list is never `nil` once read.
  defp never_nil(nil, {:list, _}), do: []
  defp never_nil(value, _type), do: value

  @doc "The `_id` value of a struct, as stored."
  @spec id_of(struct(), module()) :: term()
  def id_of(%{__struct__: module} = struct, policy) do
    %{id: id_field, types: types} = Document.options(module)
    type = Keyword.get(types, id_field) || type_of(module, id_field, policy)
    encode(type, Map.get(struct, id_field), policy)
  end

  @doc "Encodes the id given to `find_by_id`, `delete` and friends the way the document stores it."
  @spec encode_id(module(), term(), module()) :: term()
  def encode_id(module, id, policy) do
    %{id: id_field, types: types} = Document.options(module)
    type = Keyword.get(types, id_field) || type_of(module, id_field, policy)
    encode(type, id, policy)
  end

  defp type_of(module, name, policy) do
    case Enum.find(fields(module, policy), &(&1.name == name)) do
      nil -> :string
      %{type: type} -> type
    end
  end

  # -- Values ---------------------------------------------------------------------------------

  @doc "Encodes a value of `type` to its BSON form."
  @spec encode(term(), term(), module()) :: term()
  def encode(_type, nil, _policy), do: nil
  def encode(:string, value, _policy), do: to_string(value)
  def encode(:integer, value, _policy), do: value
  def encode(:float, value, _policy), do: value * 1.0
  def encode(:boolean, value, _policy), do: value
  def encode(:uuid, value, _policy), do: uuid(value)
  def encode(:object_id, value, _policy), do: object_id(value)
  def encode(:datetime, value, _policy), do: datetime(value)
  def encode(:date, %Date{} = value, _policy), do: DateTime.new!(value, ~T[12:00:00], "Etc/UTC")
  def encode(:date, value, _policy), do: encode(:date, Date.from_iso8601!(value), nil)
  def encode(:map, value, policy), do: generic(value, policy)

  def encode({:list, type}, values, policy) when is_list(values),
    do: Enum.map(values, &encode(type, &1, policy))

  def encode(module, value, policy) when is_atom(module) do
    cond do
      Arc.Types.concept?(module) ->
        primitive = Arc.Types.concept_primitive(module)
        encode(primitive, unwrap(value), policy)

      is_struct(value) ->
        to_document(value, policy)

      is_map(value) ->
        generic(value, policy)

      true ->
        generic(value, policy)
    end
  end

  def encode(_type, value, policy), do: generic(value, policy)

  @doc "Decodes a stored BSON value of `type`."
  @spec decode(term(), term(), module()) :: term()
  def decode(_type, nil, _policy), do: nil
  def decode(:string, value, _policy), do: stored_string(value)
  def decode(:integer, value, _policy) when is_float(value), do: trunc(value)
  def decode(:integer, value, _policy), do: value
  def decode(:float, value, _policy) when is_integer(value), do: value * 1.0
  def decode(:float, value, _policy), do: value
  def decode(:boolean, value, _policy), do: value

  def decode(:uuid, %BSON.Binary{binary: bin}, _policy) when byte_size(bin) == 16,
    do: format_uuid(bin)

  def decode(:uuid, value, _policy) when is_binary(value), do: String.downcase(value)

  def decode(:object_id, %BSON.ObjectId{value: bin}, _policy),
    do: Base.encode16(bin, case: :lower)

  def decode(:object_id, value, _policy) when is_binary(value), do: value
  def decode(:datetime, %DateTime{} = value, _policy), do: value

  def decode(:datetime, value, _policy) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  def decode(:date, %DateTime{} = value, _policy), do: DateTime.to_date(value)
  def decode(:date, value, _policy) when is_binary(value), do: Date.from_iso8601!(value)
  def decode(:map, value, _policy) when is_map(value), do: plain(value)

  def decode({:list, type}, values, policy) when is_list(values),
    do: Enum.map(values, &decode(type, &1, policy))

  def decode(module, value, policy) when is_atom(module) do
    cond do
      Arc.Types.concept?(module) ->
        primitive = Arc.Types.concept_primitive(module)
        struct(module, value: decode(primitive, value, policy))

      is_map(value) and function_exported?(module, :__struct__, 0) ->
        from_document(value, module, policy)

      true ->
        value
    end
  end

  def decode(_type, value, _policy), do: plain(value)

  defp unwrap(%{__struct__: _, value: inner}), do: inner
  defp unwrap(value), do: value

  defp stored_string(%BSON.ObjectId{value: bin}), do: Base.encode16(bin, case: :lower)
  defp stored_string(%BSON.Binary{binary: bin, subtype: :uuid}), do: format_uuid(bin)
  defp stored_string(value) when is_binary(value), do: value
  defp stored_string(value), do: to_string(value)

  defp uuid(%BSON.Binary{} = value), do: value

  defp uuid(value) when is_binary(value) do
    hex = String.replace(value, "-", "")

    case Base.decode16(hex, case: :mixed) do
      {:ok, bin} when byte_size(bin) == 16 -> %BSON.Binary{binary: bin, subtype: :uuid}
      _ -> raise ArgumentError, "#{inspect(value)} is not a UUID"
    end
  end

  defp uuid(%{value: inner}), do: uuid(inner)

  defp object_id(%BSON.ObjectId{} = value), do: value

  defp object_id(value) when is_binary(value) do
    case Base.decode16(value, case: :mixed) do
      {:ok, bin} when byte_size(bin) == 12 -> %BSON.ObjectId{value: bin}
      _ -> raise ArgumentError, "#{inspect(value)} is not an ObjectId"
    end
  end

  defp datetime(%DateTime{} = value), do: value
  defp datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")

  defp datetime(value) when is_binary(value) do
    {:ok, dt, _offset} = DateTime.from_iso8601(value)
    dt
  end

  defp format_uuid(
         <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2),
           e::binary-size(6)>>
       ) do
    [a, b, c, d, e] |> Enum.map_join("-", &Base.encode16(&1, case: :lower))
  end

  # Values without a declared type: plain data, with string keys.
  defp generic(%{__struct__: module} = value, policy) do
    cond do
      module in [DateTime, BSON.Binary, BSON.ObjectId] -> value
      Arc.Types.concept?(module) -> generic(value.value, policy)
      module == Date -> encode(:date, value, policy)
      module == NaiveDateTime -> datetime(value)
      true -> to_document(value, policy)
    end
  end

  defp generic(value, policy) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), generic(item, policy)} end)

  defp generic(value, policy) when is_list(value), do: Enum.map(value, &generic(&1, policy))

  defp generic(value, _policy) when is_atom(value) and not is_boolean(value),
    do: Atom.to_string(value)

  defp generic(value, _policy), do: value

  # Stored data without a declared type, as plain Elixir terms.
  defp plain(%BSON.Binary{binary: bin, subtype: :uuid}), do: format_uuid(bin)
  defp plain(%BSON.Binary{binary: bin}), do: bin
  defp plain(%BSON.ObjectId{value: bin}), do: Base.encode16(bin, case: :lower)
  defp plain(%DateTime{} = value), do: value
  defp plain(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, plain(v)} end)
  defp plain(value) when is_list(value), do: Enum.map(value, &plain/1)
  defp plain(value), do: value

  # -- Filters, sorts and updates --------------------------------------------------------------

  @doc """
  Translates a filter to stored names and values.

  Keys that are atoms are fields of the document: they take the stored name and their values are
  encoded as the field is stored. Keys that are strings are raw MongoDB and pass through, so
  `"$or"`, `"$text"` and dotted paths work. Operator maps and lists (`%{"$gt" => ..}`,
  `%{"$in" => [..]}`) are translated inside a field.
  """
  @spec filter(module(), map() | keyword() | nil, module()) :: map()
  def filter(_module, nil, _policy), do: %{}

  def filter(module, filter, policy) when is_list(filter),
    do: filter(module, Map.new(filter), policy)

  def filter(module, filter, policy) when is_map(filter) do
    Map.new(filter, fn
      {key, value} when is_atom(key) ->
        field_condition(module, key, value, policy)

      {"$" <> _ = op, clauses} when op in ["$and", "$or", "$nor"] ->
        {op, Enum.map(clauses, &filter(module, &1, policy))}

      {key, value} ->
        {key, value}
    end)
  end

  defp field_condition(module, name, value, policy) do
    case Enum.find(fields(module, policy), &(&1.name == name)) do
      nil ->
        raise ArgumentError, "#{inspect(module)} has no field #{inspect(name)}"

      %{key: key, type: type} ->
        {key, condition_value(type, value, policy)}
    end
  end

  @operators ~w($eq $ne $gt $gte $lt $lte $in $nin $all $elemMatch $size)
  defp condition_value(type, %{} = value, policy) when not is_struct(value) do
    if value != %{} and
         Enum.all?(Map.keys(value), &(is_binary(&1) and String.starts_with?(&1, "$"))) do
      Map.new(value, fn
        {op, operand} when op in ["$in", "$nin", "$all"] and is_list(operand) ->
          {op, Enum.map(operand, &operand(type, &1, policy))}

        {op, operand} when op in @operators and op not in ["$elemMatch", "$size"] ->
          {op, operand(type, operand, policy)}

        other ->
          other
      end)
    else
      operand(type, value, policy)
    end
  end

  defp condition_value(type, value, policy), do: operand(type, value, policy)

  defp operand({:list, inner}, value, policy) when not is_list(value),
    do: operand(inner, value, policy)

  defp operand({:list, inner}, value, policy), do: Enum.map(value, &operand(inner, &1, policy))
  defp operand(type, value, policy), do: encode(type, value, policy)

  @doc """
  Translates a sort (`[title: :asc, created: :desc]`) to the stored names, as an ordered list of
  `{name, 1 | -1}`.
  """
  @spec sort(module(), keyword() | nil, module()) :: [{String.t(), 1 | -1}] | nil
  def sort(_module, nil, _policy), do: nil
  def sort(_module, [], _policy), do: nil

  def sort(module, sort, policy) do
    fields = fields(module, policy)

    Enum.map(sort, fn {name, direction} ->
      key =
        case Enum.find(fields, &(&1.name == name)) do
          nil when is_binary(name) -> name
          nil -> raise ArgumentError, "#{inspect(module)} has no field #{inspect(name)}"
          %{key: key} -> key
        end

      {key, if(direction in [:desc, :descending, -1, "desc"], do: -1, else: 1)}
    end)
  end

  @doc """
  Translates an update to stored names and values. Operator maps hold fields:
  `%{"$set" => %{title: "New"}, "$inc" => %{copies: 1}}`.
  """
  @spec update(module(), map(), module()) :: map()
  def update(module, update, policy) do
    Map.new(update, fn
      {"$" <> _ = op, %{} = changes} ->
        {op,
         Map.new(changes, fn
           {key, value} when is_atom(key) -> field_condition(module, key, value, policy)
           other -> other
         end)}

      other ->
        other
    end)
  end

  @doc false
  @spec schema_fields(module()) :: [Schema.Field.t()]
  def schema_fields(module), do: Schema.model_fields(module)
end
