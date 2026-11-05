# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.Options do
  @moduledoc """
  The MongoDB options of an Arc application.

  They are the `:mongodb` option of the application's configuration, so one place configures Arc
  and its persistence:

      config :my_app, MyApp.Arc,
        mongodb: [
          server: "mongodb://localhost:27017/?replicaSet=rs0",
          database: "library"
        ]

  ## Options

    * `:server` - (required) the connection string. Read it from the environment in
      `config/runtime.exs`; keep credentials out of source control
    * `:database` - (required) the database. A named tenant is a database of its own, see
      `Arc.MongoDB.DatabaseNameResolver`
    * `:direct_connection` - connect to the one server given instead of discovering the replica
      set; when unset, the connection string decides. It does not turn a standalone server into a
      replica set, which change streams need
    * `:naming_policy` - `:none` (default), `:camel_case`, `:snake_case` or a module, see
      `Arc.MongoDB.NamingPolicy`
    * `:database_resolver` - a module implementing `Arc.MongoDB.DatabaseNameResolver`
    * `:server_resolver` - a module implementing `Arc.MongoDB.ServerResolver`
    * `:connection_resolution` - where to connect and who as, per tenant, see
      `Arc.MongoDB.ConnectionResolver`: `connection: resolver`, `identity: resolver` and
      `cache_duration:` in seconds (default `300`)
    * `:pool_size` - connections per server and identity; default `5`
  """

  alias Arc.MongoDB.NamingPolicy

  defstruct server: nil,
            database: nil,
            direct_connection: nil,
            naming_policy: NamingPolicy.None,
            database_resolver: Arc.MongoDB.DatabaseNameResolver.Default,
            server_resolver: Arc.MongoDB.ServerResolver.Default,
            connection_resolver: [connection: :default, identity: :default],
            cache_duration: 300,
            pool_size: 5

  @type t :: %__MODULE__{}

  @doc """
  The validated options of an application.

  Raises `ArgumentError` when `:server` or `:database` is missing, so a misconfigured application
  fails on the first use, not on a later query.
  """
  @spec fetch!(module()) :: t()
  def fetch!(app) do
    raw = Keyword.get(Arc.Application.state(app).config, :mongodb)

    if raw == nil do
      raise ArgumentError,
            "#{inspect(app)} has no :mongodb configuration. Set `mongodb: [server: ..., database: ...]` on the application."
    end

    key = {__MODULE__, app, :erlang.phash2(raw)}

    case :persistent_term.get(key, nil) do
      nil ->
        options = build(raw)
        :persistent_term.put(key, options)
        options

      options ->
        options
    end
  end

  @doc false
  @spec build(keyword()) :: t()
  def build(raw) do
    for key <- [:server, :database] do
      unless is_binary(raw[key]) and raw[key] != "",
        do: raise(ArgumentError, "The MongoDB option #{inspect(key)} is required.")
    end

    resolution = Keyword.get(raw, :connection_resolution, [])

    %__MODULE__{
      server: raw[:server],
      database: raw[:database],
      direct_connection: raw[:direct_connection],
      naming_policy: NamingPolicy.resolve(raw[:naming_policy]),
      database_resolver: raw[:database_resolver] || Arc.MongoDB.DatabaseNameResolver.Default,
      server_resolver: raw[:server_resolver] || Arc.MongoDB.ServerResolver.Default,
      connection_resolver: [
        connection: Keyword.get(resolution, :connection, :default),
        identity: Keyword.get(resolution, :identity, :default)
      ],
      cache_duration: Keyword.get(resolution, :cache_duration, 300),
      pool_size: raw[:pool_size] || 5
    }
  end
end
