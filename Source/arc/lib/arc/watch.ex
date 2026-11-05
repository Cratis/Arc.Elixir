# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Watch do
  @moduledoc """
  A source of change notifications for observable queries.

  `@observe watch: [...]` accepts Chronicle read model modules, and `{module, target}` pairs where
  `module` implements this behaviour. Persistence packages use it to re-run a query when their
  data changes, for example `ArcMongo.watch/1` over a MongoDB change stream.

  `subscribe/3` runs when the subscription starts, with the context of the caller (so a watcher
  can follow the caller's tenant), and must arrange for `{:arc_notify, target}` to be sent to
  `owner` whenever the watched data may have changed. Arc debounces bursts and re-runs the query.
  `unsubscribe/1` is called with the returned handle when the subscription ends.
  """

  @callback subscribe(target :: term(), ctx :: Arc.Context.t(), owner :: pid()) ::
              {:ok, handle :: term()} | {:error, term()}
  @callback unsubscribe(handle :: term()) :: :ok
end
