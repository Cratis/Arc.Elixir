# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Subscription do
  @moduledoc """
  One live subscription to an observable query.

  A subscription is a process under the application's dynamic supervisor. It runs the query,
  sends the owner `{:arc_query_result, id, %Arc.QueryResult{}}`, and sends another every time a
  watched read model changes or a topic is notified. It monitors the owner and ends with it.

  It uses `restart: :temporary`: a failing subscription ends instead of restarting and failing
  again in a loop; the client resubscribes.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Arc.{Notifier, Pipeline}

  @debounce_ms 25

  @doc """
  Starts a subscription. `spec` is a map with `:owner`, `:id`, `:descriptor`, `:query`, `:args`,
  `:ctx` and `:opts`. Requires the application to be started.
  """
  @spec start(module(), map()) :: {:ok, pid()} | {:error, term()}
  def start(app, spec) do
    DynamicSupervisor.start_child(
      Notifier.subscriptions(app),
      {__MODULE__, Map.put(spec, :app, app)}
    )
  end

  @doc "Stops a subscription."
  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.cast(pid, :stop)
  end

  @doc false
  def start_link(spec), do: GenServer.start_link(__MODULE__, spec)

  @impl true
  def init(spec) do
    Process.monitor(spec.owner)
    state = Map.merge(spec, %{pending?: false, watchers: []})
    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    chronicle =
      Keyword.take(Arc.Application.state(state.app).config[:chronicle], [:client, :namespace])

    watchers =
      for model <- state.query.watch, reduce: [] do
        acc ->
          case Chronicle.ReadModels.subscribe(model, chronicle) do
            {:ok, watcher} ->
              [watcher | acc]

            {:error, reason} ->
              Logger.warning("Arc could not watch #{inspect(model)}: #{inspect(reason)}")
              acc
          end
      end

    for topic <- state.query.topics,
        do: Registry.register(Notifier.registry(state.app), topic, nil)

    send_result(state)
    {:noreply, %{state | watchers: watchers}}
  end

  @impl true
  def handle_info({:chronicle_read_model_changed, _model, _changeset}, state),
    do: {:noreply, schedule(state)}

  def handle_info({:arc_notify, _topic}, state), do: {:noreply, schedule(state)}

  def handle_info(:rerun, state) do
    send_result(state)
    {:noreply, %{state | pending?: false}}
  end

  def handle_info({:DOWN, _ref, :process, owner, _reason}, %{owner: owner} = state),
    do: {:stop, :normal, state}

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def handle_cast(:stop, state), do: {:stop, :normal, state}

  @impl true
  def terminate(_reason, state) do
    for watcher <- state.watchers, do: Chronicle.ReadModels.unsubscribe(watcher)
    :ok
  end

  defp schedule(%{pending?: true} = state), do: state

  defp schedule(state) do
    Process.send_after(self(), :rerun, @debounce_ms)
    %{state | pending?: true}
  end

  defp send_result(state) do
    result =
      Pipeline.execute_query(state.descriptor, state.query, state.args, state.ctx, state.opts)

    send(state.owner, {:arc_query_result, state.id, result})
  end
end
