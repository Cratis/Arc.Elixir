# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Plug.DirectSocket do
  @moduledoc false

  # Direct WebSocket for one observable query route. Messages carry a string `type` of `Data`,
  # `Ping` or `Pong`; `Data` carries the query result envelope in `data`.

  @behaviour WebSock

  alias Arc.{QueryResult, Subscription}

  @impl true
  def init(%{app: app, descriptor: descriptor, query: query, ctx: ctx}) do
    spec = %{
      owner: self(),
      id: :direct,
      descriptor: descriptor,
      query: query,
      args: %{},
      ctx: ctx,
      opts: []
    }

    case Subscription.start(app, spec) do
      {:ok, subscription} -> {:ok, %{subscription: subscription}}
      {:error, _} -> {:stop, :normal, 1011, %{subscription: nil}}
    end
  end

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, %{"type" => "Ping"}} ->
        {:push, {:text, message("Pong", %{"timestamp" => now()})}, state}

      _ ->
        {:ok, state}
    end
  end

  def handle_in(_other, state), do: {:ok, state}

  @impl true
  def handle_info({:arc_query_result, _id, %QueryResult{} = result}, state),
    do: {:push, {:text, message("Data", %{"data" => QueryResult.to_wire(result)})}, state}

  def handle_info(_other, state), do: {:ok, state}

  @impl true
  def terminate(_reason, %{subscription: subscription}) when is_pid(subscription) do
    Subscription.stop(subscription)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp message(type, extra), do: Jason.encode!(Map.put(extra, "type", type))
  defp now, do: System.os_time(:millisecond)
end
