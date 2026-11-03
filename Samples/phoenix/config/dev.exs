# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

import Config

config :library, Library.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  secret_key_base:
    "dev-only-secret-key-base-for-the-library-sample-0123456789abcdef0123456789abcdef",
  code_reloader: false
