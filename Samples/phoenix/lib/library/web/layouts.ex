# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Web.Layouts do
  @moduledoc false

  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Library (LiveView)</title>
        <script src="/assets/phoenix.js"></script>
        <script src="/assets/phoenix_live_view.js"></script>
        <script>
          const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content");
          new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {params: {_csrf_token: csrf}}).connect();
        </script>
      </head>
      <body>{@inner_content}</body>
    </html>
    """
  end
end
