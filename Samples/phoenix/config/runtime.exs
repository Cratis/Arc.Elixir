# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

import Config

# Where Chronicle runs. The default matches the development image started in the README.
config :library,
  chronicle_connection_string:
    System.get_env("CHRONICLE_CONNECTION_STRING") ||
      "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000"

if config_env() == :prod do
  config :library, Library.Web.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    url: [host: System.get_env("PHX_HOST") || "localhost"],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    server: true
end
