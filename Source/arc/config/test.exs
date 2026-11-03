# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

import Config

config :logger, level: :error

config :cratis_arc, ArcFixtures.Web.Endpoint,
  secret_key_base: String.duplicate("arc-fixture-secret-", 5),
  live_view: [signing_salt: "arc-fixture-live-view"],
  server: false,
  render_errors: [formats: [html: ArcFixtures.Web.ErrorView], layout: false]
