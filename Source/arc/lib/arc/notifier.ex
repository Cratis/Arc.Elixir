# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Notifier do
  @moduledoc """
  Tells observable queries to run again.

  Queries declared with `@observe watch: [Model]` re-run when Chronicle reports a change to
  that read model. For anything else, declare `@observe topics: ["authors"]` and call
  `notify/2` when the data changes:

      Arc.Notifier.notify(MyApp.Arc, "authors")

  Subscriptions are processes registered in the application's `Registry`, so notification works
  across processes on a node. Cluster-wide fan-out is the application's choice: broadcast with
  `Phoenix.PubSub` (or `:pg`) and call `notify/2` in the receiving handler on each node.
  """

  @doc false
  @spec registry(module()) :: atom()
  def registry(app), do: Module.concat(app, Registry)

  @doc false
  @spec subscriptions(module()) :: atom()
  def subscriptions(app), do: Module.concat(app, Subscriptions)

  @doc "Notifies every observable query subscribed to `topic` on this node."
  @spec notify(module(), term()) :: :ok
  def notify(app, topic) do
    Registry.dispatch(registry(app), topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:arc_notify, topic})
    end)
  end
end
