# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.ReadModel do
  @moduledoc """
  A read model container: the module that declares queries over one model type.

  The `model` is any struct, typically a Chronicle read model. Arc infers the TypeScript shape
  from its fields, so the model stays a plain Chronicle read model.

      defmodule MyApp.Authors.Listing.Authors do
        @moduledoc "Queries over authors."
        use Arc.ReadModel, model: MyApp.Authors.Author

        @query many: true
        def all_authors(_args, _ctx), do: Chronicle.all(MyApp.Authors.Author)

        @query params: [id: :uuid], many: false
        def by_id(%{id: id}, _ctx), do: Chronicle.read_model(MyApp.Authors.Author, id)

        @observe many: true, watch: [MyApp.Authors.Author]
        def live_authors(_args, _ctx), do: Chronicle.all(MyApp.Authors.Author)
      end

  Each annotated function takes `(args, ctx)` where `args` is a map of the declared, converted
  parameters, and returns `{:ok, value}` or `{:error, results}`.

  ## `@query` / `@observe` options

    * `:params` - keyword list of `name: type`, or `name: {type, optional: true}`
    * `:many` - the query returns a list (default `true`); Arc applies `page`, `pageSize`,
      `sortBy` and `sortDirection` to lists unless the function returns an `Arc.Page`
    * `:authorize` / `:allow_anonymous` - override the module-level declaration
    * `:http_method` - `:get` or `:query` to prefer one in the generated client

  `@observe` additionally takes:

    * `:watch` - Chronicle read model modules; the query re-runs when any of them changes
    * `:topics` - `Arc.Notifier` topics that re-run the query when notified
  """

  @doc false
  defmacro __using__(opts) do
    model = Keyword.fetch!(opts, :model)

    quote do
      import Arc.ReadModel, only: [authorize: 1, allow_anonymous: 0]
      Module.register_attribute(__MODULE__, :arc_queries, accumulate: true)
      Module.register_attribute(__MODULE__, :query, [])
      Module.register_attribute(__MODULE__, :observe, [])
      @arc_model unquote(model)
      @arc_authorization nil
      @on_definition {Arc.ReadModel, :on_definition}
      @before_compile Arc.ReadModel
    end
  end

  @doc "Declares who may run every query of the module. See `Arc.Authorization`."
  defmacro authorize(requirement) do
    quote do: @arc_authorization(unquote(requirement))
  end

  @doc "Allows anonymous callers for every query of the module."
  defmacro allow_anonymous do
    quote do: @arc_authorization(allow_anonymous: true)
  end

  @doc false
  def on_definition(env, kind, name, args, _guards, _body) when kind in [:def] do
    query = Module.get_attribute(env.module, :query)
    observe = Module.get_attribute(env.module, :observe)

    cond do
      query != nil -> record(env, name, args, query, false)
      observe != nil -> record(env, name, args, observe, true)
      true -> :ok
    end

    Module.delete_attribute(env.module, :query)
    Module.delete_attribute(env.module, :observe)
  end

  def on_definition(_env, _kind, _name, _args, _guards, _body), do: :ok

  defp record(env, name, args, opts, observable?) do
    if length(args) != 2 do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "query #{name} must take two arguments, (args, ctx)"
    end

    already = Module.get_attribute(env.module, :arc_queries) || []

    unless Enum.any?(already, fn {n, _, _, _} -> n == name end) do
      doc = Arc.Docs.summary(Module.get_attribute(env.module, :doc))
      opts = if is_list(opts), do: opts, else: []
      Module.put_attribute(env.module, :arc_queries, {name, opts, observable?, doc})
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    {namespace, name} = Arc.Naming.module_parts(env.module)

    module_auth =
      Module.get_attribute(env.module, :arc_authorization) |> Arc.Authorization.normalize()

    model = Module.get_attribute(env.module, :arc_model)
    doc = Arc.Docs.summary(Module.get_attribute(env.module, :moduledoc))

    queries =
      env.module
      |> Module.get_attribute(:arc_queries)
      |> Enum.reverse()
      |> Enum.map(fn {fun, opts, observable?, qdoc} ->
        build_query(fun, opts, observable?, qdoc, module_auth)
      end)

    descriptor = %Arc.Descriptor{
      kind: :read_model,
      module: env.module,
      name: name,
      namespace: namespace,
      doc: doc,
      model: model,
      queries: queries,
      authorization: module_auth
    }

    quote do
      def __arc__, do: unquote(Macro.escape(descriptor))
    end
  end

  defp build_query(fun, opts, observable?, doc, module_auth) do
    params =
      opts
      |> Keyword.get(:params, [])
      |> Enum.map(fn
        {name, {type, popts}} -> param(name, type, Keyword.get(popts, :optional, false))
        {name, type} -> param(name, type, false)
      end)

    authorization =
      cond do
        Keyword.has_key?(opts, :authorize) ->
          Arc.Authorization.normalize(Keyword.get(opts, :authorize))

        Keyword.get(opts, :allow_anonymous, false) ->
          Arc.Authorization.normalize(allow_anonymous: true)

        true ->
          module_auth
      end

    %Arc.Descriptor.Query{
      name: fun,
      doc: doc,
      params: params,
      many?: Keyword.get(opts, :many, true),
      observable?: observable?,
      watch: Keyword.get(opts, :watch, []),
      topics: Keyword.get(opts, :topics, []),
      http_method: Keyword.get(opts, :http_method),
      authorization: authorization
    }
  end

  defp param(name, type, optional?) do
    %Arc.Schema.Field{name: name, type: type, nullable?: optional?, required?: not optional?}
  end
end

defmodule Arc.Page do
  @moduledoc """
  A page of results from a query that pages itself, for example a query over a database.

  Return `{:ok, %Arc.Page{items: items, total: total}}` from a query and Arc reports the
  `paging` block of the result envelope from it instead of paging a list in memory.
  """
  defstruct items: [], total: 0, page: 0, size: 0

  @type t :: %__MODULE__{
          items: [term()],
          total: non_neg_integer(),
          page: non_neg_integer(),
          size: non_neg_integer()
        }
end
