# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Counters.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = chronicle() ++ [Counters.Arc] ++ server()
    Supervisor.start_link(children, strategy: :one_for_one, name: Counters.Supervisor)
  end

  defp chronicle do
    if Application.get_env(:counters, :start_chronicle, true) do
      [
        {Chronicle.Client,
         connection_string: Application.fetch_env!(:counters, :chronicle_connection_string),
         event_store: "counters-plug",
         otp_app: :counters}
      ]
    else
      []
    end
  end

  defp server do
    if Application.get_env(:counters, :start_server, true),
      do: [{Bandit, plug: Counters.Router, port: Application.fetch_env!(:counters, :port)}],
      else: []
  end
end
