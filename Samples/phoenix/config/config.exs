# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

import Config

config :library, Library.Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: Library.Web.ErrorHTML], layout: false],
  live_view: [signing_salt: "library-live-view"]

config :library, Library.Arc,
  # `arc:` is read by the compiler; this is the runtime view of the same application.
  segments_to_skip: 1,
  introspection: :anonymous

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
