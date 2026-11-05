# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.Supervisor do
  @moduledoc false
  # The processes of the MongoDB integration of one Arc application: the connections (one driver
  # topology per server and identity) and the change stream watchers that observable queries share.

  use Supervisor

  def start_link(app), do: Supervisor.start_link(__MODULE__, app, name: name(app))

  def name(app), do: Module.concat(app, MongoDB)
  def topologies(app), do: Module.concat(app, MongoDB.Topologies)
  def watchers(app), do: Module.concat(app, MongoDB.Watchers)

  @impl true
  def init(app) do
    children = [
      {DynamicSupervisor, name: topologies(app), strategy: :one_for_one},
      {Arc.MongoDB.Connections, app},
      {Registry, keys: :duplicate, name: Arc.MongoDB.Watch.registry(app)},
      {Registry, keys: :unique, name: Arc.MongoDB.Watcher.names(app)},
      {DynamicSupervisor, name: watchers(app), strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
