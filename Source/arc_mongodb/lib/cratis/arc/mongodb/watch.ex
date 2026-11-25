# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.MongoDB.Watch do
  @moduledoc """
  Makes observable queries follow a MongoDB collection.

  Use `Cratis.Arc.MongoDB.watch/1` in an `@observe` declaration:

      @observe many: true, watch: [Cratis.Arc.MongoDB.watch(Library.Books.Book)]
      def live_books(_args, ctx), do: {:ok, Cratis.Arc.MongoDB.all({ctx, Library.Books.Book})}

  A subscription resolves the collection for **its own tenant** and listens there, so each tenant
  of an application sees only the changes of its own database, and a placement from
  `Cratis.Arc.MongoDB.ConnectionResolver` is followed.

  One change stream is open per database (and server) however many queries observe it: see
  `Cratis.Arc.MongoDB.Watcher`. A change to a watched collection re-runs the query; bursts are debounced
  by `Cratis.Arc.Subscription`. Observation is not an event log: it says *that* the collection changed, and
  the query decides what to send. It needs a replica set or a sharded cluster.
  """

  @behaviour Cratis.Arc.Watch

  @doc false
  @spec registry(module()) :: atom()
  def registry(app), do: Module.concat(app, MongoDB.Observers)

  @impl true
  def subscribe(document, %Cratis.Arc.Context{} = ctx, owner) do
    if owner != self(),
      do: raise(ArgumentError, "Arc.MongoDB.Watch.subscribe/3 must run in the observing process.")

    collection = Cratis.Arc.MongoDB.collection(ctx, document)
    key = {collection.connection, collection.database, collection.name}
    {:ok, _} = Registry.register(registry(ctx.application), key, document)

    case Cratis.Arc.MongoDB.Watcher.ensure(collection) do
      :ok ->
        {:ok, {ctx.application, key}}

      {:error, reason} ->
        Registry.unregister(registry(ctx.application), key)
        {:error, reason}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  @impl true
  def unsubscribe({app, key}) do
    Registry.unregister(registry(app), key)
    :ok
  end
end
