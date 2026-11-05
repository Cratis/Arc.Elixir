# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

import Config

# One place for what differs between machines.
#
#   PORT         where the sample listens (default 4002)
#   MONGODB_URL  a MongoDB *replica set*; change streams, which the observable MongoDB queries
#                use, need one (default mongodb://localhost:27017/?replicaSet=rs0, see
#                docker-compose.yml)
#
# Everything except the MongoDB page works without a MongoDB.

config :showcase, port: String.to_integer(System.get_env("PORT", "4002"))

config :showcase, Samples.Arc,
  # Who is signed in and which tenant is selected, demo style: the browser sends them as headers
  # (and as cookies, which is all a WebSocket or an EventSource can send), and a plug in front of
  # Arc turns the cookies into headers. The unsigned `x-ms-client-principal` headers are trusted
  # only because this is a sample. A real application authenticates with its own scheme, or
  # trusts them only behind an ingress that sets them.
  authentication: [Arc.Authentication.MicrosoftIdentityPlatform],
  trust_forwarded_identity_headers: true,
  introspection: :anonymous,
  # Tenant by header, `x-cratis-tenant-id`. Other resolvers: `:query`, `:claim`, `:subdomain`.
  tenancy: [resolver: :header],
  # Cross-cutting authorization for a whole namespace, see Samples.CrossCuttingAuthorization.Filter.
  filters: [Samples.CrossCuttingAuthorization.Filter],
  mongodb: [
    server: System.get_env("MONGODB_URL", "mongodb://localhost:27017/?replicaSet=rs0"),
    database: "samples",
    naming_policy: :camel_case
  ]
