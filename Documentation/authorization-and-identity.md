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

The React packages ask `GET /.cratis/me` for the signed-in user. It is registered only when you provide a details module:

```elixir
config :my_app, MyApp.Arc, identity_details: MyApp.IdentityDetails
```

```elixir
defmodule MyApp.IdentityDetails do
  def details(%Arc.Principal{} = principal), do: {:ok, %{avatar_url: MyApp.Avatars.url(principal.id)}}
end
```

`details/1` returns `{:ok, map}` or `:forbidden`. The response is `{id, name, isAuthenticated, isAuthorized, roles, details}`, 401 when the caller is not signed in, 403 when `details/1` returns `:forbidden`. Without `identity_details`, the route is not registered, and the client treats that as "no identity endpoint".

## Introspection access

`/.cratis/commands` and `/.cratis/queries` list your operations, routes and schemas to anyone who can reach them. By default they require an authenticated caller. Set `introspection: :anonymous` for development or `introspection: false` to remove them. See [Configuration](configuration.md).

## Next steps

- [Hosting on Phoenix](hosting/phoenix.md#csrf-and-cookie-sessions) covers cookie sessions and CSRF.
