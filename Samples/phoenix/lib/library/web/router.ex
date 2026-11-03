# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Web.Router do
  @moduledoc false

  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Library.Web.Layouts, :root}
  end

  scope "/", Library.Web do
    pipe_through :browser

    live "/live/authors", AuthorsLive
  end

  scope "/", Library.Web do
    get "/health", HealthController, :show
  end
end
