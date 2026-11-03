# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      chronicle() ++
        [
          # Arc after Chronicle: observable queries watch Chronicle read models.
          Library.Arc,
          Library.Web.Endpoint
        ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Library.Supervisor)
  end

  # Tests run against Chronicle's in-memory kernel, started per test by Arc.Test.Case.
  defp chronicle do
    if Application.get_env(:library, :start_chronicle, true) do
      [
        {Chronicle.Client,
         connection_string: Application.fetch_env!(:library, :chronicle_connection_string),
         event_store: "library-phoenix",
         otp_app: :library}
      ]
    else
      []
    end
  end
end
