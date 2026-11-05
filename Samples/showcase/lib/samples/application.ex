# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [Samples.Store, Samples.Arc, {Arc.MongoDB, application: Samples.Arc}] ++
        tickers() ++ server()

    Supervisor.start_link(children, strategy: :one_for_one, name: Samples.Supervisor)
  end

  # The feeds that change on their own: the Ticker every second, the Showcase every three.
  defp tickers do
    if Application.get_env(:showcase, :start_tickers, true),
      do: [Samples.Ticker.Clock, Samples.QueryShowcase.Clock, Samples.AuthenticationQueries.Clock],
      else: []
  end

  defp server do
    if Application.get_env(:showcase, :start_server, true) do
      port = Application.fetch_env!(:showcase, :port)
      [{Bandit, plug: Samples.Router, port: port}]
    else
      []
    end
  end
end
