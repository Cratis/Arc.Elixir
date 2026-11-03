# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

import Config

config :library, Library.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  secret_key_base:
    "dev-only-secret-key-base-for-the-library-sample-0123456789abcdef0123456789abcdef",
  code_reloader: false

# Development tools such as Lens sign in by sending the unsigned x-ms-client-principal headers.
# Trust them only behind an ingress that authenticates callers and strips client-supplied identity
# headers; never in production configuration.
config :library, Library.Arc,
  authentication: [Arc.Authentication.ClientPrincipal, Arc.Authentication.FromAssigns],
  trust_forwarded_identity_headers: true
