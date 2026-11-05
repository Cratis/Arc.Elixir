# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.Document do
  @moduledoc """
  Declares how a struct is stored in MongoDB.

  A document is any struct, so a Chronicle read model or an Arc read model's struct can be stored
  as it is. Use this module to say more than the struct's defaults can:

      defmodule Library.Books.Book do
        use Arc.MongoDB.Document, collection: "books", types: [id: :uuid, published: :date]

        defstruct id: "", title: "", authors: [], published: nil
      end

  ## Options

    * `:collection` - the collection name; by default the naming policy's name for the module
    * `:id` - the field stored as `_id`; default `:id`
    * `:types` - field type overrides, as for `Arc.ReadModel`. Types come from the struct's
      defaults (`nil` and `""` are strings, `[]` a list of strings), so state `:uuid`, `:date`,
      `:datetime`, `:object_id`, a concept module or a nested struct module where the default does not say it

  ## What is stored

  | Type | BSON |
  | --- | --- |
  | `:string`, `:integer`, `:float`, `:boolean` | the same |
  | `:uuid` | binary, subtype 4 (the Standard UUID representation) |
  | `:object_id` | `ObjectId`, as a 24 character hexadecimal string in the struct |
  | `:datetime` | UTC date time, to the millisecond |
  | `:date` | UTC date time at noon of the day |
  | `{:list, type}` | array; never `nil` when read |
  | `:map` | embedded document |
  | a `Chronicle.Concept` | the primitive it wraps, with no wrapper document |
  | a nested struct module | embedded document, named by the same policy |

  Members that the struct does not know are ignored when reading, and members missing from a
  document take the struct's defaults.
  """

  @doc false
  defmacro __using__(opts) do
    quote do
      @doc false
      def __arc_mongo__ do
        opts = unquote(opts)

        %{
          collection: Keyword.get(opts, :collection),
          id: Keyword.get(opts, :id, :id),
          types: Keyword.get(opts, :types, [])
        }
      end

      @doc false
      # The types Arc sees: the same declaration, with `:object_id` as the string it is in the struct.
      def __arc_types__ do
        for {name, type} <- Keyword.get(unquote(opts), :types, []),
            do: {name, if(type == :object_id, do: :string, else: type)}
      end
    end
  end

  @doc false
  @spec options(module()) :: %{collection: String.t() | nil, id: atom(), types: keyword()}
  def options(module) do
    Code.ensure_loaded?(module)

    if function_exported?(module, :__arc_mongo__, 0),
      do: module.__arc_mongo__(),
      else: %{collection: nil, id: :id, types: []}
  end
end
