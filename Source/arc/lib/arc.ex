# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc do
  @moduledoc """
  Arc for Elixir: an opinionated CQRS application framework for Phoenix and Plug, on Cratis
  Chronicle.

  You declare *what* your application does as plain modules, and Arc serves it:

    * `Arc.Command` - a request struct with a `handle/2` that decides and returns events
    * `Arc.ReadModel` - queries over a Chronicle read model, snapshot or observable
    * `Arc.Application` - the supervised runtime that discovers them
    * `Arc.Plug` - the Arc HTTP contract, so `@cratis/arc`, `@cratis/arc.react` and Cratis
      Components work against it unchanged
    * `Arc.LiveView` - the same commands and queries, called in-process from LiveView
    * `Arc.ProxyGenerator` - opt-in TypeScript proxies for React
    * `Arc.Test` - ExUnit scenarios that run the real pipelines

  Use `execute/3` and `query/5` to call the pipelines from code.
  """

  alias Arc.{Context, CommandResult, Pipeline, QueryResult}

  @doc """
  Executes a command through the full pipeline.

  `command` is a command struct, or a `{module, wire_map}` pair to bind a wire map first.

  ## Options

    * `:principal`, `:tenant`, `:correlation_id`, `:causation_id`, `:metadata` - context values
    * `:validate_only` - authorize and validate without handling
  """
  @spec execute(module(), struct() | {module(), map()}, keyword()) :: CommandResult.t()
  def execute(application, command, opts \\ [])

  def execute(application, %{__struct__: module} = command, opts),
    do: execute(application, module, command, opts)

  def execute(application, {module, wire}, opts) when is_atom(module) and is_map(wire),
    do: execute(application, module, wire, opts)

  defp execute(application, module, input, opts) do
    {pipeline_opts, context_opts} = Keyword.split(opts, [:validate_only])
    Pipeline.execute_command(module, input, context(application, context_opts), pipeline_opts)
  end

  @doc """
  Executes a query of a read model by function name.

  `args` are the declared parameters, as a map keyed by name (atoms or strings).

  ## Options

    * context options as for `execute/3`
    * `:page`, `:page_size`, `:sort_by`, `:sort_direction` - see `Arc.Pipeline.execute_query/5`
  """
  @spec query(module(), module(), atom(), map(), keyword()) :: QueryResult.t()
  def query(application, read_model, name, args \\ %{}, opts \\ []) do
    descriptor = read_model.__arc__()

    query =
      Enum.find(descriptor.queries, &(&1.name == name)) ||
        raise ArgumentError, "#{inspect(read_model)} has no query #{inspect(name)}"

    {query_opts, context_opts} =
      Keyword.split(opts, [:page, :page_size, :sort_by, :sort_direction])

    raw = Map.new(args, fn {k, v} -> {Arc.Naming.camel(k), v} end)
    Pipeline.execute_query(descriptor, query, raw, context(application, context_opts), query_opts)
  end

  @doc """
  A new UUID v4 string, for a command key such as a new author's id.

      %RegisterAuthor{id: Arc.new_id(), name: "Ada"}
  """
  @spec new_id() :: String.t()
  defdelegate new_id(), to: Context, as: :new_correlation_id

  @doc "Builds a context for `application` from the given options."
  @spec context(module(), keyword()) :: Context.t()
  def context(application, opts \\ []) do
    chronicle = Arc.Application.state(application).config[:chronicle]
    base = Context.new(Keyword.merge([application: application, chronicle: chronicle], opts))
    %{base | chronicle: Arc.Tenancy.chronicle_options(base.chronicle, base.tenant)}
  end
end
