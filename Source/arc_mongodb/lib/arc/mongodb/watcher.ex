# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.Watcher do
  @moduledoc """
  The change stream of one database, shared by every observer of it.

  MongoDB limits the number of open change streams a deployment serves well, so a stream per
  observable query subscription would not scale. A watcher opens **one** database-level stream
  per server and database, started by the first observer and stopped some time after the last
  one has gone, and tells the observers of each collection that it changed
  (`{:arc_notify, document}`, see `Arc.MongoDB.Watch`).

  It survives failures: a broken stream is reopened with backoff from its resume token, and when
  the position cannot be resumed it starts afresh. Either way every observer is told to run again,
  because changes may have gone by in between. A watcher also tells everyone once its stream is
  open, which covers a change made between an observer's first run and the stream opening.
  """

  use GenServer, restart: :transient

  require Logger

  @idle_check_ms 30_000
  @first_backoff_ms 500
  @max_backoff_ms 10_000

  @doc false
  @spec names(module()) :: atom()
  def names(app), do: Module.concat(app, MongoDB.WatcherNames)

  @doc false
  @spec ensure(Arc.MongoDB.Collection.t()) :: :ok | {:error, term()}
  def ensure(collection, attempts \\ 3) do
    name = {:via, Registry, {names(collection.app), {collection.connection, collection.database}}}

    result =
      case GenServer.whereis(name) do
        nil -> start(collection, name)
        pid -> {:ok, pid}
      end

    with {:ok, pid} <- result do
      try do
        GenServer.call(pid, :keep)
      catch
        :exit, _ when attempts > 1 -> ensure(collection, attempts - 1)
        :exit, reason -> {:error, reason}
      end
    end
  end

  defp start(collection, name) do
    spec = {__MODULE__, {collection, name}}

    case DynamicSupervisor.start_child(Arc.MongoDB.Supervisor.watchers(collection.app), spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def start_link({collection, name}), do: GenServer.start_link(__MODULE__, collection, name: name)

  @impl true
  def init(collection) do
    Process.flag(:trap_exit, true)
    Process.send_after(self(), :idle_check, @idle_check_ms)

    state = %{
      app: collection.app,
      connection: collection.connection,
      topology: collection.topology,
      database: collection.database,
      token: nil,
      reader: nil,
      ready?: false,
      failures: 0
    }

    {:ok, open(state)}
  end

  @impl true
  def handle_call(:keep, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info({:token, reader, token}, %{reader: reader} = state) do
    # The first token means the stream is open: tell everyone, a change may have preceded it.
    if state.ready? do
      {:noreply, %{state | token: token}}
    else
      notify_all(state)
      {:noreply, %{state | token: token, ready?: true, failures: 0}}
    end
  end

  def handle_info({:change, reader, collection}, %{reader: reader} = state) do
    notify(state, collection)
    {:noreply, state}
  end

  def handle_info({:EXIT, reader, reason}, %{reader: reader} = state) do
    if reason not in [:normal, :shutdown] do
      Logger.warning(
        "The MongoDB change stream of #{state.database} stopped (#{inspect(reason)}); reopening it."
      )
    end

    failures = state.failures + 1
    # A position that cannot be resumed is dropped after a few attempts.
    token = if failures >= 3, do: nil, else: state.token
    Process.send_after(self(), :reopen, backoff(failures))
    {:noreply, %{state | reader: nil, token: token, failures: failures, ready?: false}}
  end

  def handle_info(:reopen, state) do
    {:noreply, open(state)}
  end

  def handle_info(:idle_check, state) do
    Process.send_after(self(), :idle_check, @idle_check_ms)

    if observers(state) == 0 do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{reader: reader}) when is_pid(reader) do
    Process.unlink(reader)
    Process.exit(reader, :kill)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # -- Reading the stream -----------------------------------------------------------------------

  defp open(state) do
    parent = self()
    topology = state.topology
    database = state.database
    token = state.token

    reader =
      spawn_link(fn ->
        me = self()
        on_token = fn token -> send(parent, {:token, me, token}) end
        opts = [database: database, batch_size: 100, max_time: 1_000] ++ resume(token)

        # Only the collection and kind of each change matter, not what changed.
        pipeline = [%{"$project" => %{"ns" => 1, "operationType" => 1}}]

        case Mongo.watch_db(topology, pipeline, on_token, opts) do
          {:error, error} ->
            exit({:change_stream, error})

          stream ->
            Enum.each(stream, fn
              %{"ns" => %{"coll" => collection}} -> send(parent, {:change, me, collection})
              %{"operationType" => "dropDatabase"} -> send(parent, {:change, me, :all})
              _ -> :ok
            end)

            exit(:stream_ended)
        end
      end)

    %{state | reader: reader}
  end

  defp resume(nil), do: []
  defp resume(token), do: [resume_after: token]

  defp backoff(failures),
    do: min(@first_backoff_ms * Integer.pow(2, failures - 1), @max_backoff_ms)

  # -- Observers --------------------------------------------------------------------------------

  defp registry(state), do: Arc.MongoDB.Watch.registry(state.app)

  defp notify(state, :all), do: notify_all(state)

  defp notify(state, collection) do
    key = {state.connection, state.database, collection}

    Registry.dispatch(registry(state), key, fn entries ->
      for {pid, document} <- entries, do: send(pid, {:arc_notify, document})
    end)
  end

  defp notify_all(state) do
    pattern = [{{{state.connection, state.database, :_}, :"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}]

    for {pid, document} <- Registry.select(registry(state), pattern),
        do: send(pid, {:arc_notify, document})

    :ok
  end

  defp observers(state) do
    pattern = [{{{state.connection, state.database, :_}, :_, :_}, [], [true]}]
    registry(state) |> Registry.select(pattern) |> length()
  end
end
