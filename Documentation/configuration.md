---
title: Configuration reference
description: Reference for every Arc for Elixir application option, the proxy generation settings in mix.exs, and the routes, headers and defaults each of them controls.
---

Options go to `use Arc.Application` and are merged under `config :my_app, MyApp.Arc, […]`, so deployment configuration wins.

```elixir
defmodule MyApp.Arc do
  use Arc.Application, otp_app: :my_app, segments_to_skip: 1
end

# config/runtime.exs
config :my_app, MyApp.Arc, introspection: :authenticated
```

## Application options

| Option | Default | Meaning |
| --- | --- | --- |
| `otp_app` | required | The OTP application scanned for commands and read models |
| `artifacts` | scan `otp_app` | An explicit list of modules instead of scanning |
| `route_prefix` | `"api"` | First segment of conventional routes |
| `segments_to_skip` | `1` | Leading module-name segments dropped from routes, slice locations and proxy folders |
| `chronicle` | `[]` | Options passed to every Chronicle call, for example `[client: MyApp.Chronicle]` |
| `authentication` | `[Arc.Authentication.FromAssigns]` | `Arc.Authentication` handlers, in order |
| `policies` | `[]` | `[name: PolicyModule]` for `Arc.Policy` |
| `identity_details` | the single `Arc.Identity.Provider` found | The identity provider to use. Without one, `/.cratis/me` is not served |
| `trust_forwarded_identity_headers` | `false` | Let `Arc.Authentication.MicrosoftIdentityPlatform` accept the `x-ms-client-principal*` headers. Unsigned, only behind an authenticating ingress; required for the two options below |
| `forwarded_identity` | `[enabled: false, audience: "", keys: []]` | Verify the signed `x-cratis-forwarded-identity-signature` envelope with 1 to 8 `[key_id:, secret_base64:]` keys. See [Signed forwarded identity](authorization-and-identity.md#signed-forwarded-identity) |
| `on_behalf_of` | `[enabled: false, issuer: "", audience: "", service: "", clock_skew: 30, signing_keys: []]` | Accept an RS256 assertion that an actor acts for the user, with `[key_id:, public_key_pem:]` keys. See [Acting on behalf of a user](authorization-and-identity.md#acting-on-behalf-of-a-user) |
| `tenant_header` | `"x-cratis-tenant-id"` | Header the `:header` tenancy resolver reads, and the fallback of the `:subdomain` one |
| `tenancy` | `[]` (the header resolver) | How the tenant is resolved: `resolver:` (`:header`, `:query`, `:claim`, `:subdomain`, `:fixed`, `:development` or a module), `header:`, `query_parameter:`, `claim_type:`, `base_domain:` and `tenant_id:`. See [Tenancy](tenancy.md) |
| `filters` | `[]` | `Arc.Filter` modules: cross-cutting rules that run for every command and query |
| `mongodb` | none | The MongoDB options of `cratis_arc_mongodb`, see [MongoDB](mongodb.md) |
| `correlation_header` | `"x-correlation-id"` | Header reused and echoed |
| `max_body_bytes` | `1_000_000` | Request body limit |
| `introspection` | `:authenticated` | Who may read the five discovery routes (commands, queries, identity schema, users, tenants): `:authenticated`, `:anonymous` or `false` to remove them. `/.cratis/me` is unaffected |
| `expose_exceptions` | `false` | Include exception messages and stack traces in results. Never enable in production |

## Proxy generation

Set in `mix.exs`, under `arc:`. Without an `output`, nothing is generated.

| Option | Default | Meaning |
| --- | --- | --- |
| `application` | required | The `Arc.Application` module |
| `output` | required | The directory to generate into |
| `remove_stale` | `true` | Delete generated files for artifacts that no longer exist |

Add `compilers: Mix.compilers() ++ [:arc]` to generate on compile.

## Plug options

| Plug | Option | Meaning |
| --- | --- | --- |
| `Arc.Plug` | `application` | The application module (required) |
| `Arc.Plug.SinglePage` | `root` | The directory of the built frontend (required) |
| `Arc.Plug.SinglePage` | `index` | Index document; default `"index.html"` |
| `Arc.Plug.SinglePage` | `api_prefixes` | Prefixes that are never the SPA; default `["/api/", "/.cratis/"]` |

## Formatter

Add `import_deps: [:cratis_arc]` to `.formatter.exs` so `field`, `authorize` and `response` stay free of parentheses.
