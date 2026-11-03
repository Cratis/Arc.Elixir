# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

import Config

config :logger, level: :error
config :library, start_chronicle: false

config :library, Library.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test-only-secret-key-base-for-the-library-sample-0123456789abcdef0123456789abcdef",
  server: false
