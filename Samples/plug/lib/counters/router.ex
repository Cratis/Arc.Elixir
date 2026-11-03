# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Counters.Router do
  @moduledoc """
  A plain Plug pipeline: no Phoenix. Arc answers its own routes and passes everything else on.
  """

  use Plug.Router

  plug Arc.Plug, application: Counters.Arc
  plug :match
  plug :dispatch

  get "/health", do: send_resp(conn, 200, "ok")
  match _, do: send_resp(conn, 404, "not found")
end
