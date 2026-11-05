# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Router do
  @moduledoc """
  A plain Plug pipeline, no Phoenix. Arc answers its own routes (commands, queries, the identity
  and discovery routes and both multiplexed hubs) and passes everything else on.
  """

  use Plug.Router

  plug(Plug.Logger, log: :debug)
  plug(Samples.Web.CookieIdentity)
  plug(Arc.Plug, application: Samples.Arc)
  plug(:match)
  plug(:dispatch)

  get("/health", do: send_resp(conn, 200, "ok"))

  # The built React app, when it exists (`npm run build` in `frontend`).
  match _ do
    root = Application.app_dir(:showcase, "priv/spa")

    if File.dir?(root) do
      opts = Arc.Plug.SinglePage.init(root: root, api_prefixes: ["/api/", "/.cratis/", "/health"])
      conn |> Arc.Plug.SinglePage.call(opts) |> finish()
    else
      send_resp(conn, 404, "Run the React app: cd frontend && npm install && npm run dev")
    end
  end

  defp finish(%Plug.Conn{halted: true} = conn), do: conn
  defp finish(conn), do: send_resp(conn, 404, "not found")
end
