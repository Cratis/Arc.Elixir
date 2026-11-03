# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Web.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :library

  @session_options [
    store: :cookie,
    key: "_library",
    signing_salt: "library-session",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # LiveView's browser scripts, straight from the dependencies: no asset pipeline needed.
  plug Plug.Static, at: "/assets", from: {:phoenix, "priv/static"}, only: ~w(phoenix.js)

  plug Plug.Static,
    at: "/assets",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.js)

  plug Plug.RequestId
  plug Plug.Session, @session_options

  # Who is calling: turns the demo sign-in into the principal Arc reads.
  plug Library.Web.DevAuth

  # The Arc HTTP contract: commands, queries, observable queries and /.cratis/*.
  # Non-Arc requests pass through to the rest of the pipeline.
  plug Arc.Plug, application: Library.Arc

  # The built React SPA (../frontend/dist), when it exists. Never swallows the API or LiveView.
  plug Library.Web.Spa

  plug Library.Web.Router
end
