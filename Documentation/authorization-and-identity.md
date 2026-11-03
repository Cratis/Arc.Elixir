---
title: Authorization and identity
description: Require roles, policies or authentication on commands and queries, plug in your own authentication, and serve the caller's identity to the frontend.
---

Arc decides what a caller may do. It does not decide who the caller is: that stays with the authentication you already have. Arc reads the result.

## Require something

Declare the requirement on the artifact. With no declaration it is open.

```elixir
authorize roles: ["editor"]      # at least one of these roles
authorize :authenticated         # any signed-in caller
authorize policy: :can_publish   # a named policy
allow_anonymous()                # explicitly open
```

On a read model, `authorize` applies to every query in the module. A single query overrides it: `@query authorize: [roles: ["admin"]]` or `@query allow_anonymous: true`.

A caller who is not signed in and hits a requirement gets `isAuthorized: false` with status 403 and the reason in `authorizationFailureReason`. Authorization runs before binding and validation, so a denied caller learns nothing about the request's validity.

## Policies

A policy is a module that decides from the full context. Register it by name on the application.

```elixir
defmodule MyApp.Policies.CanPublish do
  @behaviour Arc.Policy

  @impl true
  def authorize?(ctx, _subject), do: ctx.principal.claims["publisher"] == true
end
```

```elixir
config :my_app, MyApp.Arc, policies: [can_publish: MyApp.Policies.CanPublish]
```

`subject` is the command struct for a command and `:query` for a query.

## Tell Arc who is calling

An `Arc.Principal` holds `id`, `name`, `authenticated?`, `roles` and `claims`. Arc builds one from your authentication through a chain of handlers, in the order of the `authentication:` option. The first handler that recognizes the request decides:

| A handler returns | Result |
| --- | --- |
| `{:authenticated, principal}` | The chain stops with that principal |
| `:failed` | Terminal: later handlers do not run and the caller gets a generic 401 |
| `:anonymous` | Not recognized; the next handler tries. Anonymous is final only when none recognized the request |

The default handler, `Arc.Authentication.FromAssigns`, reads what your own plug assigned:

- `conn.assigns.arc_principal`, an `Arc.Principal`;
- `conn.assigns.current_scope.user`, the `phx.gen.auth` shape;
- `conn.assigns.current_user`, a map with `:id` and optionally `:name`, `:email`, `:roles`.

So with `phx.gen.auth`, put `Arc.Plug` after the plug that fetches the current user and nothing else is needed. For tokens or a gateway, write a plug that assigns `arc_principal`, or implement `Arc.Authentication`:

```elixir
defmodule MyApp.TokenAuthentication do
  @behaviour Arc.Authentication

  @impl true
  def authenticate(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case MyApp.Tokens.verify(token) do
          {:ok, user} -> {:authenticated, Arc.Principal.new(user.id, user.name, roles: user.roles)}
          :error -> :failed
        end

      _ ->
        :anonymous
    end
  end
end
```

The Phoenix sample's `Library.Web.DevAuth` is a demo sign-in built the same way; it is for demonstration, not production.

## Identity for the frontend

Authentication establishes who is calling. Identity is what the UI shows about them: name, roles and application-specific details. The React packages read it from `GET /.cratis/me`, and LiveView reads the same data in process.

Identity is presentation data and never an authorization decision. It adds no trusted claims and protects no command or query; those authorize themselves.

### Provide the details

Implement `Arc.Identity.Provider`. Arc finds it in your application, so there is nothing to register.

```elixir
# From: Samples/phoenix/lib/library/identity/provider.ex
      use Arc.Identity.Provider, details: Library.Identity.IdentityDetails

      @impl true
      def details(%Arc.Identity.Context{name: name, principal: principal}) do
        {:ok,
         %Library.Identity.IdentityDetails{
           display_name: "Hello, #{name}",
           can_rename: "editor" in principal.roles
         }}
      end
```

`details:` names the type of the details, an `Arc.Schema` module:

```elixir
# From: Samples/phoenix/lib/library/identity/identity_details.ex
      use Arc.Schema

      schema do
        field :display_name, :string, required: true
        field :can_rename, :boolean, required: true
      end
```

It does three jobs. `/.cratis/identity-details/schema` serves its JSON schema. [Proxy generation](react-proxies.md) turns it into a TypeScript class, so `useIdentity` is typed. And the wire uses its `camelCase` field names.

The callback receives an `Arc.Identity.Context` built from the request principal on every call, so cache expensive lookups inside it:

| Field | Meaning |
| --- | --- |
| `id` | The identity identifier; `"unknown"` when the principal has none |
| `name` | The display name |
| `claims` | `{type, value}` string pairs from the principal, plus a `{"role", role}` pair per role |
| `principal` | The full `Arc.Principal` |

It returns `{:ok, details}`, or `{:unauthorized, details}` when the user is signed in but may not use the application at all. An `Arc.Identity.Details` struct says the same with a flag. An application without a provider does not serve `/.cratis/me`, and the client treats that as "no identity endpoint". Give the application more than one provider and startup fails, naming them; pick one with the `identity_details:` option.

### What the endpoint answers

| Caller | Status | Body |
| --- | --- | --- |
| Not signed in | 401 | empty |
| Signed in, provider says `:unauthorized` | 403 | empty |
| Signed in and allowed | 200 | `{id, name, isAuthenticated, isAuthorized, roles, details}` |

Every response is private: `Cache-Control: no-store, private` and `Vary: Cookie`, because it holds per-user data. Do not let a shared cache override that. Arc does not read or write an identity cookie.

### In LiveView

`assign_identity/2` assigns the same `Arc.Identity.Result` the endpoint would serve. See [LiveView](live-view.md#identity).

### Development users and tenants

Tools such as Lens read `/.cratis/users` and `/.cratis/tenants` to offer users and tenants to sign in as. Implement `Arc.Identity.UsersProvider` and `Arc.Identity.TenantsProvider` in development-only modules; Arc discovers them and concatenates what they return.

```elixir
# From: Samples/phoenix/lib/library/identity/dev_users.ex
      @behaviour Arc.Identity.UsersProvider

      @impl true
      def users do
        [
          %Arc.Identity.User{user_id: "ada", user_details: "ada", roles: []},
          %Arc.Identity.User{user_id: "ed", user_details: "ed", roles: ["editor"]}
        ]
      end
```

A user is listed on the wire as a `microsoftIdentity` client principal (`identityProvider`, `userId`, `userDetails`, `userRoles`, `claims`) plus `details`; a tenant as `{id, name}`. A list is not proof of authentication or membership, and it is not how a request's tenant is chosen. Keep these modules out of production builds.

## Signing in through an ingress or Lens

`Arc.Authentication.MicrosoftIdentityPlatform` authenticates from the Microsoft identity platform headers an ingress supplies, and from the same headers Lens injects in development. It matches Arc on .NET:

| Header | Content |
| --- | --- |
| `x-ms-client-principal` | The base64 client principal: `identityProvider`, `userId`, `userDetails`, `userRoles`, `claims` |
| `x-ms-client-principal-id` | The identifier; the RFC 8187 `UTF-8''…` form is percent-decoded |
| `x-ms-client-principal-name` | The name, used when `userDetails` is empty |

All three headers are required on the unsigned path. The id comes from `x-ms-client-principal-id`, the name from `userDetails`, and the roles from `userRoles` and from claims of the type `http://schemas.microsoft.com/ws/2008/06/identity/claims/role`. The identity provider is kept as the claim `urn:cratis:arc:identity:provider`. A payload that is not valid base64 JSON fails the request with 401.

```elixir
config :my_app, MyApp.Arc,
  authentication: [Arc.Authentication.MicrosoftIdentityPlatform, Arc.Authentication.FromAssigns],
  trust_forwarded_identity_headers: true
```

:::caution[Unsigned headers are not proof]
Base64 is not a signature. The handler ignores the headers, and the request stays anonymous, until you set `trust_forwarded_identity_headers: true`. Set it only when every request reaches the application through an ingress that authenticates callers, strips caller-supplied identity headers and writes trusted replacements, and when nothing can reach the application directly. The setting applies to every route, including the discovery routes. The first time an untrusted request carries the headers, Arc logs a warning naming the setting. Prefer the signed envelope below.
:::

## Signed forwarded identity

The signed envelope lets the application verify that the identity headers came from your ingress, so it does not have to trust the network. Arc verifies it exactly as Arc on .NET does: an HMAC-SHA256 over a canonical form of the request, carried in `x-cratis-forwarded-identity-signature` as `v1.<keyId>.<timestamp>.<nonce>.<mac>`.

```elixir
config :my_app, MyApp.Arc,
  authentication: [Arc.Authentication.MicrosoftIdentityPlatform],
  trust_forwarded_identity_headers: true,
  forwarded_identity: [
    enabled: true,
    audience: "my-app",
    keys: [[key_id: "k1", secret_base64: System.fetch_env!("ARC_FORWARDED_IDENTITY_KEY")]]
  ]
```

Each secret is exactly 32 random bytes, standard-base64 encoded. Configure one to eight keys, so a key can be rotated while the old one still verifies. With the envelope enabled, a request with identity headers but no valid signature is rejected with 401; the headers alone are never enough.

The MAC covers the audience, key id, timestamp, nonce, method, canonical path and query, the tenant header, and the identity headers, so none can be changed in flight. A signature is accepted for 60 seconds in the past and 30 seconds ahead, and a nonce can be used once per audience and key.

:::note[Replay memory is per node]
Seen nonces are kept in memory by a process that `Arc.Application` starts, up to 100,000 entries. A replay is refused only on the node that saw the original, so give each node its own key or route a caller to one node if that matters. If the application is not started, verification fails closed.
:::

## Acting on behalf of a user

An ingress can let a support person or a service act as a user. It adds a signed assertion that names the actor, and Arc then answers with the user as the principal and the actor beside it, as Arc on .NET does.

```elixir
config :my_app, MyApp.Arc,
  trust_forwarded_identity_headers: true,
  on_behalf_of: [
    enabled: true,
    issuer: "https://auth.example.com",
    audience: "my-app",
    service: "my-app",
    clock_skew: 30,
    signing_keys: [[key_id: "authproxy-2026", public_key_pem: File.read!("authproxy.pub.pem")]]
  ]
```

The assertion is an RS256 JWS. Arc checks the signature against RSA public keys of at least 2048 bits (a private key is refused), then the issuer, audience, optional service, the key id, a lifetime of at most five minutes, a unique `jti`, the HTTP method and path, the tenant, and hashes that bind the assertion to the user and actor headers. Any failure is a 401 with a fixed message and never reveals which check failed.

On success `Arc.Principal.actor/1` returns the acting principal and `Arc.Principal.acted_on_behalf_of?/1` is true. Chronicle records the actor as the cause of an append, on behalf of the user. Without the `on_behalf_of` option, a request that carries an assertion is rejected rather than ignored.

## Discovery routes

`/.cratis/commands`, `/.cratis/queries`, `/.cratis/identity-details/schema`, `/.cratis/users` and `/.cratis/tenants` list your operations, schemas and development fixtures to anyone who can reach them. By default they require an authenticated caller (401 otherwise). Set `introspection: :anonymous` for development, or `introspection: false` to remove all five. `/.cratis/me` is not affected. See [Configuration](configuration.md).

## Next steps

- [Hosting on Phoenix](hosting/phoenix.md#csrf-and-cookie-sessions) covers cookie sessions and CSRF.
- [React and generated proxies](react-proxies.md) generates the typed identity details class.
