# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB do
  @moduledoc """
  MongoDB persistence for Arc.

  The package gives an Arc application document storage with the conventions its other parts
  expect: the tenant of the request selects the database, structs and BSON documents convert by a
  naming policy, concepts store as plain values, and observable queries re-run when a collection
  changes. Chronicle and event sourcing are not required.

  ## Set up

  Add the package, start it after the Arc application and describe the connection on that
  application:

      # mix.exs
      {:cratis_arc_mongodb, "~> 0.0"}

      # config/runtime.exs
      config :my_app, MyApp.Arc,
        mongodb: [
          server: System.get_env("MONGODB_URL", "mongodb://localhost:27017/?replicaSet=rs0"),
          database: "library"
        ]

      # lib/my_app/application.ex
      children = [MyApp.Arc, {Arc.MongoDB, application: MyApp.Arc}, MyApp.Endpoint]

  See `Arc.MongoDB.Options` for every option. Change streams, which observation needs, require a
  replica set or a sharded cluster.

  ## Use

  Documents are structs (`Arc.MongoDB.Document`). A collection is resolved from the context, so
  the tenant of the request picks the database with no code of yours:

      defmodule Library.Books.Listing.Books do
        use Arc.ReadModel, model: Library.Books.Book

        @observe many: true, watch: [Arc.MongoDB.watch(Library.Books.Book)]
        def live_books(_args, ctx), do: {:ok, Arc.MongoDB.all({ctx, Library.Books.Book})}
      end

      defmodule Library.Books.AddBook do
        use Arc.Command
        # ...
        def handle(command, ctx) do
          book = %Library.Books.Book{id: command.id, title: command.title}
          {:ok, _} = Arc.MongoDB.insert({ctx, Library.Books.Book}, book)
          {:ok, nil}
        end
      end

  Wherever a function takes a `collection`, it accepts a `Arc.MongoDB.Collection` or the pair
  `{context, document_module}`, which is resolved for you.

  ## Tenancy

  The tenant is `ctx.tenant` (see `Arc.Tenancy`). The default tenant uses the configured
  database and a named tenant `"<database>+<tenant>"`, see `Arc.MongoDB.DatabaseNameResolver`.
  Naming is not authorization: a resolver selects, and the application checks that the caller
  belongs to the tenant. `Arc.MongoDB.ConnectionResolver` places tenants on servers and
  credentials of their own.
  """

  alias Arc.MongoDB.{Codec, Collection, Connections}

  @type scope :: Collection.t() | {Arc.Context.t(), module()}

  @doc """
  Starts the MongoDB processes of an Arc application.

      {Arc.MongoDB, application: MyApp.Arc}

  Start it after the application: observable queries use it.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    app = Keyword.fetch!(opts, :application)

    %{
      id: {__MODULE__, app},
      start: {Arc.MongoDB.Supervisor, :start_link, [app]},
      type: :supervisor
    }
  end

  # -- Collections ------------------------------------------------------------------------------

  @doc """
  The collection of `document` for the tenant of `ctx`.

  Raises when the connection cannot be resolved: the configuration is missing, a resolver failed or
  the credentials are not usable.

  ## Options

    * `:purpose` - `:runtime` (default) or `:schema`, which the connection resolvers can answer
      differently, for example with a more privileged identity for creating indexes
  """
  @spec collection(Arc.Context.t(), module(), keyword()) :: Collection.t()
  def collection(%Arc.Context{} = ctx, document, opts \\ []) do
    app = ctx.application || raise ArgumentError, "The context has no Arc application."
    options = Arc.MongoDB.Options.fetch!(app)
    purpose = Keyword.get(opts, :purpose, :runtime)

    case Connections.connect(app, ctx.tenant, purpose) do
      {:ok, connection} ->
        %Collection{
          app: app,
          tenant: ctx.tenant,
          purpose: purpose,
          topology: connection.topology,
          connection: connection.key,
          database: connection.database,
          name: Codec.collection_name(document, options.naming_policy),
          document: document,
          policy: options.naming_policy
        }

      {:error, reason} ->
        raise "Arc could not resolve the MongoDB connection for tenant #{inspect(ctx.tenant)}: #{message(reason)}"
    end
  end

  @doc """
  The name of the database the tenant of `ctx` resolves to.
  """
  @spec database(Arc.Context.t()) :: String.t()
  def database(%Arc.Context{} = ctx), do: collection(ctx, Arc.MongoDB.Document).database

  @doc "The collection name and database of a scope, for diagnostics and tests."
  @spec locate(scope()) :: {database :: String.t(), collection :: String.t()}
  def locate(scope) do
    %Collection{database: database, name: name} = resolve(scope)
    {database, name}
  end

  defp resolve(%Collection{} = collection), do: collection
  defp resolve({%Arc.Context{} = ctx, document}), do: collection(ctx, document)

  # -- Reads ------------------------------------------------------------------------------------

  @doc """
  Every document of the collection.
  """
  @spec all(scope(), keyword()) :: [struct()]
  def all(scope, opts \\ []), do: find(scope, %{}, opts)

  @doc """
  Documents matching `filter`.

  The filter uses the fields of the struct as atoms (`%{title: "Dune"}`), with MongoDB operators
  where needed (`%{copies: %{"$gt" => 1}}`), and raw string keys for everything else
  (`%{"$or" => [...]}`). See `Arc.MongoDB.Codec.filter/3`.

  ## Options

    * `:sort` - `[title: :asc, published: :desc]`
    * `:limit`, `:skip`
  """
  @spec find(scope(), map() | keyword() | nil, keyword()) :: [struct()]
  def find(scope, filter \\ %{}, opts \\ []) do
    c = resolve(scope)
    query = Codec.filter(c.document, filter, c.policy)

    driver_opts =
      [database: c.database]
      |> put_if(:sort, Codec.sort(c.document, opts[:sort], c.policy))
      |> put_if(:limit, opts[:limit])
      |> put_if(:skip, opts[:skip])

    c.topology
    |> Mongo.find(c.name, query, driver_opts)
    |> Enum.map(&Codec.from_document(&1, c.document, c.policy))
  end

  @doc "The first document matching `filter`, or `nil`."
  @spec find_one(scope(), map() | keyword() | nil, keyword()) :: struct() | nil
  def find_one(scope, filter, opts \\ []),
    do: scope |> find(filter, Keyword.put(opts, :limit, 1)) |> List.first()

  @doc "The document with `id`, or `nil`."
  @spec find_by_id(scope(), term()) :: struct() | nil
  def find_by_id(scope, id) do
    c = resolve(scope)

    case Mongo.find_one(c.topology, c.name, %{"_id" => Codec.encode_id(c.document, id, c.policy)},
           database: c.database
         ) do
      nil -> nil
      document -> Codec.from_document(document, c.document, c.policy)
    end
  end

  @doc """
  Loads a document for a command, for its `provide/2` callback: the current state the command
  decides from. The document is `nil` when there is none, and lands in `ctx.provided` under `name`
  (default: the snake_case name of the document module, `:book` for `Library.Books.Book`).

      def provide(%__MODULE__{id: id}, ctx), do: Arc.MongoDB.provide(ctx, Library.Books.Book, id)

      def handle(%__MODULE__{} = command, ctx) do
        case ctx.provided.book do
          nil -> ...
        end
      end
  """
  @spec provide(Arc.Context.t(), module(), term(), atom() | nil) :: {:ok, map()}
  def provide(%Arc.Context{} = ctx, document, id, name \\ nil) do
    name =
      name ||
        document |> Arc.MongoDB.NamingPolicy.type_name() |> Macro.underscore() |> String.to_atom()

    {:ok, %{name => find_by_id({ctx, document}, id)}}
  end

  @doc "How many documents match `filter`."
  @spec count(scope(), map() | keyword() | nil) :: non_neg_integer()
  def count(scope, filter \\ %{}) do
    c = resolve(scope)

    case Mongo.count_documents(c.topology, c.name, Codec.filter(c.document, filter, c.policy),
           database: c.database
         ) do
      {:ok, count} -> count
      {:error, error} -> raise error
    end
  end

  @doc """
  A page of documents as the `Arc.Page` a query returns, paged and sorted in the database.

  The page, page size and sorting come from what the caller asked for (`ctx.query`), so a query is
  just

      def books(_args, ctx), do: {:ok, Arc.MongoDB.page({ctx, Book}, %{})}

  and the client's paging and sorting arguments reach MongoDB. Without a page size every
  document is returned in one page.

  ## Options

    * `:sort` - the order when the caller asked for none
    * `:page`, `:page_size` - override what the caller asked for
  """
  @spec page(scope(), map() | keyword() | nil, keyword()) :: Arc.Page.t()
  def page(scope, filter \\ %{}, opts \\ []) do
    c = resolve(scope)
    asked = ask(scope)
    page = opts[:page] || asked[:page] || 0
    size = opts[:page_size] || asked[:page_size] || 0
    total = count(c, filter)

    sort = requested_sort(c, asked) || opts[:sort]

    items =
      if size > 0,
        do: find(c, filter, sort: sort, skip: page * size, limit: size),
        else: find(c, filter, sort: sort)

    %Arc.Page{items: items, total: total, page: page, size: size}
  end

  defp ask({%Arc.Context{query: query}, _document}), do: query
  defp ask(_), do: %{}

  defp requested_sort(c, asked) do
    with sort_by when is_binary(sort_by) <- asked[:sort_by],
         %{name: name} <-
           Enum.find(Codec.fields(c.document, c.policy), &(Arc.Naming.camel(&1.name) == sort_by)) do
      [{name, asked[:sort_direction] || :asc}]
    else
      _ -> nil
    end
  end

  # -- Writes -----------------------------------------------------------------------------------

  @doc """
  Stores a new document. Returns `{:ok, document}`, or `{:error, :duplicate}` when a document with
  that id (or a unique index) exists.
  """
  @spec insert(scope(), struct()) :: {:ok, struct()} | {:error, term()}
  def insert(scope, %{__struct__: _} = document) do
    c = resolve(scope)

    case Mongo.insert_one(c.topology, c.name, Codec.to_document(document, c.policy),
           database: c.database
         ) do
      {:ok, _} -> {:ok, document}
      {:error, error} -> {:error, failure(c, error)}
    end
  end

  @doc "Stores several new documents."
  @spec insert_many(scope(), [struct()]) :: {:ok, [struct()]} | {:error, term()}
  def insert_many(_scope, []), do: {:ok, []}

  def insert_many(scope, documents) do
    c = resolve(scope)
    docs = Enum.map(documents, &Codec.to_document(&1, c.policy))

    case Mongo.insert_many(c.topology, c.name, docs, database: c.database) do
      {:ok, _} -> {:ok, documents}
      {:error, error} -> {:error, failure(c, error)}
    end
  end

  @doc """
  Stores a document, replacing the one with its id and creating it when there is none (an upsert).
  """
  @spec save(scope(), struct()) :: {:ok, struct()} | {:error, term()}
  def save(scope, %{__struct__: _} = document) do
    c = resolve(scope)
    doc = Codec.to_document(document, c.policy)

    case Mongo.replace_one(c.topology, c.name, %{"_id" => doc["_id"]}, doc,
           database: c.database,
           upsert: true
         ) do
      {:ok, _} -> {:ok, document}
      {:error, error} -> {:error, failure(c, error)}
    end
  end

  @doc """
  Applies an update to the document with `id`: `%{"$set" => %{title: "New"}, "$inc" => %{copies: 1}}`.

  Returns `{:ok, modified}` with `0` when there is no such document.
  """
  @spec update(scope(), term(), map()) :: {:ok, non_neg_integer()} | {:error, term()}
  def update(scope, id, update) do
    c = resolve(scope)

    case Mongo.update_one(
           c.topology,
           c.name,
           %{"_id" => Codec.encode_id(c.document, id, c.policy)},
           Codec.update(c.document, update, c.policy),
           database: c.database
         ) do
      {:ok, %{modified_count: modified}} -> {:ok, modified}
      {:error, error} -> {:error, failure(c, error)}
    end
  end

  @doc "Applies an update to every document matching `filter`."
  @spec update_many(scope(), map() | keyword() | nil, map()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def update_many(scope, filter, update) do
    c = resolve(scope)

    case Mongo.update_many(
           c.topology,
           c.name,
           Codec.filter(c.document, filter, c.policy),
           Codec.update(c.document, update, c.policy),
           database: c.database
         ) do
      {:ok, %{modified_count: modified}} -> {:ok, modified}
      {:error, error} -> {:error, failure(c, error)}
    end
  end

  @doc "Deletes the document with `id`. Returns `{:ok, deleted}`, `0` when there was none."
  @spec delete(scope(), term()) :: {:ok, non_neg_integer()} | {:error, term()}
  def delete(scope, id) do
    c = resolve(scope)

    case Mongo.delete_one(
           c.topology,
           c.name,
           %{"_id" => Codec.encode_id(c.document, id, c.policy)},
           database: c.database
         ) do
      {:ok, %{deleted_count: deleted}} -> {:ok, deleted}
      {:error, error} -> {:error, failure(c, error)}
    end
  end

  @doc "Deletes every document matching `filter`."
  @spec delete_many(scope(), map() | keyword() | nil) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def delete_many(scope, filter \\ %{}) do
    c = resolve(scope)

    case Mongo.delete_many(c.topology, c.name, Codec.filter(c.document, filter, c.policy),
           database: c.database
         ) do
      {:ok, %{deleted_count: deleted}} -> {:ok, deleted}
      {:error, error} -> {:error, failure(c, error)}
    end
  end

  @doc """
  Creates an index, for example the unique index behind a rule such as "no two authors with the
  same name". Insert and save report a violation as `{:error, :duplicate}`.

      Arc.MongoDB.create_index({ctx, Author}, [name: :asc], unique: true)

  Indexes are per database, so create them for every tenant that needs them. Use
  `purpose: :schema` on the collection when the connection resolvers hand out a more privileged
  identity for schema changes.
  """
  @spec create_index(scope(), keyword(), keyword()) :: :ok | {:error, term()}
  def create_index(scope, keys, opts \\ []) do
    c = resolve(scope)
    sort = Codec.sort(c.document, keys, c.policy)

    index =
      [key: sort, name: opts[:name] || index_name(sort), unique: opts[:unique] || false]
      |> put_if(:sparse, opts[:sparse])

    case Mongo.create_indexes(c.topology, c.name, [index], database: c.database) do
      :ok -> :ok
      {:error, error} -> {:error, failure(c, error)}
    end
  end

  defp index_name(sort),
    do: Enum.map_join(sort, "_", fn {key, direction} -> "#{key}_#{direction}" end)

  # -- Observation ------------------------------------------------------------------------------

  @doc """
  Makes an observable query re-run when `document`'s collection changes.

      @observe many: true, watch: [Arc.MongoDB.watch(Library.Books.Book)]

  The change stream is shared by every observer of the database, and follows the tenant of each
  subscription. See `Arc.MongoDB.Watch`.
  """
  @spec watch(module()) :: {module(), module()}
  def watch(document), do: {Arc.MongoDB.Watch, document}

  # -- Helpers ----------------------------------------------------------------------------------

  defp put_if(opts, _key, nil), do: opts
  defp put_if(opts, key, value), do: Keyword.put(opts, key, value)

  defp failure(c, %Mongo.WriteError{write_errors: [%{"code" => 11_000} | _]}), do: duplicate(c)
  defp failure(c, %Mongo.Error{code: 11_000}), do: duplicate(c)

  defp failure(c, %Mongo.Error{code: code} = error) when code in [13, 18] do
    Connections.invalidate(c.app, c.tenant, c.purpose)
    error
  end

  defp failure(_c, error), do: error

  defp duplicate(_c), do: :duplicate

  defp message(reason) when is_binary(reason), do: reason
  defp message(reason), do: inspect(reason)
end
