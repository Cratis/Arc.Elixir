# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.Connections do
  @moduledoc false
  # Resolves the connection of a tenant: runs the configured resolvers (cached), names the database
  # and finds or starts the driver topology for the server and identity it arrives at. Topologies
  # are shared per server and identity and never across identities.

  use GenServer

  alias Arc.MongoDB.{Connection, Options, ResolvedConnection}

  @refresh_margin_seconds 60
  @ready_timeout_ms 5_000

  def start_link(app), do: GenServer.start_link(__MODULE__, app, name: name(app))

  def name(app), do: Module.concat(app, MongoDB.Connections)

  @doc """
  Resolves the connection for a tenant and purpose.
  """
  @spec connect(module(), String.t() | nil, :runtime | :schema) ::
          {:ok, Connection.t()} | {:error, term()}
  def connect(app, tenant, purpose \\ :runtime) do
    options = Options.fetch!(app)

    with {:ok, resolved} <- resolution(app, options, tenant, purpose),
         {:ok, topology, key} <- topology(app, options, resolved) do
      database = resolved.database || options.database_resolver.resolve(tenant, options)
      {:ok, %Connection{topology: topology, database: database, key: key}}
    end
  end

  @doc "Drops the cached resolution of a tenant, so the next connection resolves again."
  @spec invalidate(module(), String.t() | nil, :runtime | :schema) :: :ok
  def invalidate(app, tenant, purpose \\ :runtime) do
    :ets.delete(table(app), {:resolution, scope_tenant(tenant), purpose})
    :ok
  end

  # -- Resolution -------------------------------------------------------------------------------

  defp resolution(app, options, tenant, purpose) do
    key = {:resolution, scope_tenant(tenant), purpose}
    now = System.os_time(:second)

    case :ets.lookup(table(app), key) do
      [{^key, expires, resolved}] when expires > now ->
        {:ok, resolved}

      _ ->
        with {:ok, resolved} <- resolve(options, tenant, purpose) do
          :ets.insert(table(app), {key, expiry(resolved, options, now), resolved})
          {:ok, resolved}
        end
    end
  end

  defp expiry(%ResolvedConnection{expires_at: %DateTime{} = at}, _options, _now),
    do: DateTime.to_unix(at) - @refresh_margin_seconds

  defp expiry(_resolved, options, now), do: now + options.cache_duration

  defp resolve(options, tenant, purpose) do
    request = %{
      storage: "MongoDB",
      purpose: purpose,
      scope: %{"tenant" => scope_tenant(tenant)}
    }

    base = %ResolvedConnection{connection_string: options.server_resolver.resolve(options)}

    Enum.reduce_while([:connection, :identity], {:ok, base}, fn slot, {:ok, acc} ->
      case run(options.connection_resolver[slot], request) do
        {:ok, answer} -> {:cont, {:ok, apply_answer(acc, answer)}}
        :unchanged -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp scope_tenant(tenant), do: if(Arc.Tenancy.default?(tenant), do: "Default", else: tenant)

  defp run(:default, _request), do: :unchanged
  defp run(nil, _request), do: :unchanged

  defp run({:template, options}, request),
    do: Arc.MongoDB.ConnectionResolver.Template.resolve(request, options)

  defp run({:http, options}, request),
    do: Arc.MongoDB.ConnectionResolver.Http.resolve(request, options)

  defp run(module, request) when is_atom(module), do: module.resolve(request)

  # A part set later wins; the identity is replaced as a whole.
  defp apply_answer(base, answer) do
    %ResolvedConnection{
      connection_string: answer.connection_string || base.connection_string,
      database: answer.database || base.database,
      schema: answer.schema || base.schema,
      identity: answer.identity || base.identity,
      expires_at: earliest(base.expires_at, answer.expires_at)
    }
  end

  defp earliest(nil, other), do: other
  defp earliest(other, nil), do: other
  defp earliest(a, b), do: if(DateTime.compare(a, b) == :lt, do: a, else: b)

  # -- Topologies -------------------------------------------------------------------------------

  defp topology(_app, _options, %ResolvedConnection{identity: %{access_token: token}})
       when is_binary(token) and token != "" do
    {:error,
     "MONGODB-OIDC access tokens are not supported by the MongoDB driver for Elixir. " <>
       "Resolve a user name and password instead."}
  end

  defp topology(app, options, resolved) do
    identity = resolved.identity || %{}
    key = {resolved.connection_string, identity[:user_name], :erlang.phash2(identity[:password])}

    case :ets.lookup(table(app), {:topology, key}) do
      [{_, pid}] ->
        if Process.alive?(pid), do: {:ok, pid, key}, else: start(app, options, resolved, key)

      [] ->
        start(app, options, resolved, key)
    end
  end

  defp start(app, options, resolved, key),
    do: GenServer.call(name(app), {:start, options, resolved, key}, 30_000)

  # -- GenServer --------------------------------------------------------------------------------

  @impl true
  def init(app) do
    :ets.new(table(app), [:named_table, :public, read_concurrency: true])
    {:ok, %{app: app}}
  end

  @impl true
  def handle_call({:start, options, resolved, key}, _from, %{app: app} = state) do
    reply =
      case :ets.lookup(table(app), {:topology, key}) do
        [{_, pid}] ->
          if Process.alive?(pid),
            do: {:ok, pid, key},
            else: start_topology(app, options, resolved, key)

        [] ->
          start_topology(app, options, resolved, key)
      end

    {:reply, reply, state}
  end

  defp start_topology(app, options, resolved, key) do
    spec = %{
      id: key,
      start: {Mongo, :start_link, [driver_options(options, resolved)]},
      restart: :permanent
    }

    case DynamicSupervisor.start_child(Arc.MongoDB.Supervisor.topologies(app), spec) do
      {:ok, pid} ->
        # The driver finds its servers in the background; do not hand the topology out before it
        # can serve, or the first operation fails on a server that is merely not known yet.
        case wait_until_ready(pid, System.monotonic_time(:millisecond) + @ready_timeout_ms) do
          :ok ->
            :ets.insert(table(app), {{:topology, key}, pid})
            {:ok, pid, key}

          :timeout ->
            # Keeping a topology that cannot serve would hang every operation until it can.
            DynamicSupervisor.terminate_child(Arc.MongoDB.Supervisor.topologies(app), pid)

            {:error,
             "MongoDB is not reachable at #{host(resolved.connection_string)}. " <>
               "Is it running, and is it a replica set? See docker-compose.yml of the sample."}
        end

      {:error, {:already_started, pid}} ->
        :ets.insert(table(app), {{:topology, key}, pid})
        {:ok, pid, key}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def wait_until_ready(topology, deadline) do
    # The driver finds its servers in the background. Until one has answered it has no session
    # pool, and an operation then crashes the topology instead of failing, so wait for the pool.
    ready? =
      try do
        match?(%{session_pool: pool} when not is_nil(pool), Mongo.Topology.get_state(topology)) and
          match?({:ok, _}, Mongo.ping(topology))
      rescue
        _ -> false
      catch
        :exit, _ -> false
      end

    cond do
      ready? ->
        :ok

      System.monotonic_time(:millisecond) < deadline ->
        Process.sleep(50)
        wait_until_ready(topology, deadline)

      true ->
        :timeout
    end
  end

  @doc false
  def driver_options(options, resolved) do
    parsed =
      case Mongo.UrlParser.parse_url(url: resolved.connection_string) do
        {:error, reason} ->
          raise ArgumentError, "The MongoDB connection string is not valid: #{inspect(reason)}"

        parsed ->
          parsed
      end

    # A database in the connection string is where it authenticates by default; operations name
    # their own database per call.
    parsed =
      parsed
      |> Keyword.put_new(:database, options.database)
      |> Keyword.put(:pool_size, Keyword.get(parsed, :pool_size, options.pool_size))

    parsed =
      if options.direct_connection == true, do: Keyword.put(parsed, :type, :single), else: parsed

    case resolved.identity do
      %{user_name: user, password: password} when is_binary(user) ->
        auth_source = parsed[:auth_source] || connection_database(resolved) || "admin"

        Keyword.merge(parsed, username: user, password: password || "", auth_source: auth_source)

      _ ->
        parsed
    end
  end

  # The hosts of a connection string, without credentials.
  defp host(url) do
    case Regex.run(~r{^mongodb(?:\+srv)?://(?:[^@/]*@)?([^/?]+)}, url) do
      [_, hosts] -> hosts
      _ -> "the configured server"
    end
  end

  defp connection_database(%{connection_string: url}) do
    case Regex.run(~r{^mongodb(?:\+srv)?://[^/]+/([^?]+)}, url) do
      [_, database] -> database
      _ -> nil
    end
  end

  defp table(app), do: Module.concat(app, MongoDB.ConnectionsTable)
end
