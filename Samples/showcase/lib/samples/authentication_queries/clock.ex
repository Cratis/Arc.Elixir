# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.AuthenticationQueries.Clock do
  @moduledoc "Refreshes the authentication streams every two seconds."

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(nil) do
    schedule()
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    Arc.Notifier.notify(Samples.Arc, "authentication")
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :tick, 2_000)
end
