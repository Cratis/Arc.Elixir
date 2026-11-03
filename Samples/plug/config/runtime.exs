# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

import Config

config :counters,
  chronicle_connection_string:
    System.get_env("CHRONICLE_CONNECTION_STRING") ||
      "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000",
  port: String.to_integer(System.get_env("PORT") || "4001")
