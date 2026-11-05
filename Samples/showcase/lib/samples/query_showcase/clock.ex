# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.QueryShowcase.Clock do
  @moduledoc "Updates the showcase items every three seconds."

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(nil) do
    schedule()
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    Samples.Store.update(:showcase, "showcase", &(&1 + 1))
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :tick, 3_000)
end
