# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Filter do
  @moduledoc """
  A cross-cutting rule that runs for commands and queries, whatever their own declarations say.

  `authorize` protects one artifact. A filter protects many: a whole namespace, or everything that
  matches a rule. Register filters on the application; they run in order, after the artifact's own
  authorization and before validation or the query:

      config :my_app, MyApp.Arc, filters: [MyApp.SecuredNamespace]

      defmodule MyApp.SecuredNamespace do
        @behaviour Arc.Filter

        @impl true
        def on_command(ctx, %Arc.Descriptor{namespace: ["MyApp", "Secured" | _]}),
          do: require_role(ctx)

        def on_command(_ctx, _descriptor), do: :ok

        @impl true
        def on_query(ctx, %Arc.Descriptor{namespace: ["MyApp", "Secured" | _]}, _query),
          do: require_role(ctx)

        def on_query(_ctx, _descriptor, _query), do: :ok

        defp require_role(ctx) do
          if "Secured" in ctx.principal.roles,
            do: :ok,
            else: {:unauthorized, "Role 'Secured' is required."}
        end
      end

  Both callbacks are optional. A filter answers

    * `:ok` - carry on
    * `{:unauthorized, reason}` - the caller may not: the result is not authorized (HTTP 403) and
      carries the reason. For an observable query the subscription ends with `Unauthorized`
    * `{:error, results}` - reject with validation results

  A filter sees the *descriptor* of the artifact (`Arc.Descriptor`, with `module`, `name` and
  `namespace`) and the context, not the payload.
  """

  @type outcome :: :ok | {:unauthorized, String.t()} | {:error, term()}

  @callback on_command(Arc.Context.t(), Arc.Descriptor.t()) :: outcome()
  @callback on_query(Arc.Context.t(), Arc.Descriptor.t(), Arc.Descriptor.Query.t()) :: outcome()
  @optional_callbacks on_command: 2, on_query: 3

  @doc false
  @spec run_command(Arc.Context.t(), Arc.Descriptor.t()) :: outcome()
  def run_command(ctx, descriptor) do
    run(filters(ctx), :on_command, [ctx, descriptor], 2)
  end

  @doc false
  @spec run_query(Arc.Context.t(), Arc.Descriptor.t(), Arc.Descriptor.Query.t()) :: outcome()
  def run_query(ctx, descriptor, query) do
    run(filters(ctx), :on_query, [ctx, descriptor, query], 3)
  end

  defp filters(%Arc.Context{application: nil}), do: []

  defp filters(%Arc.Context{application: app}),
    do: Keyword.get(Arc.Application.state(app).config, :filters, [])

  defp run(filters, callback, args, arity) do
    Enum.reduce_while(filters, :ok, fn filter, :ok ->
      if Code.ensure_loaded?(filter) and function_exported?(filter, callback, arity) do
        case apply(filter, callback, args) do
          :ok -> {:cont, :ok}
          other -> {:halt, other}
        end
      else
        {:cont, :ok}
      end
    end)
  end
end
