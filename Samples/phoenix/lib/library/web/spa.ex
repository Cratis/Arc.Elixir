# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Web.Spa do
  @moduledoc false

  # Serves the built React app when it exists; otherwise passes the request on.

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    root = Application.app_dir(:library, "priv/spa")

    if File.dir?(root) do
      Arc.Plug.SinglePage.call(
        conn,
        Arc.Plug.SinglePage.init(
          root: root,
          api_prefixes: ["/api/", "/.cratis/", "/live", "/assets", "/health"]
        )
      )
    else
      conn
    end
  end
end
