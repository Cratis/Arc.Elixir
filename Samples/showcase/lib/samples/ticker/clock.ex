# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Ticker.Clock do
  @moduledoc "Ticks every second, so a client sees updates without doing anything."

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(nil) do
    schedule()
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    Samples.Store.update(:ticker, "ticker", fn ticker ->
      %{ticker | count: ticker.count + 1, last_updated: DateTime.utc_now()}
    end)

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :tick, 1_000)
end
