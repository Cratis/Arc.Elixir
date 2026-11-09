---
title: Tenancy
description: Choose how Arc for Elixir resolves the tenant of each request, and how that tenant selects the Chronicle namespace and the MongoDB database your code uses.
---

A request is for one tenant. Tenancy has three separate decisions, and Arc treats them separately:

| Decision | Who makes it |
| --- | --- |
| **Selection**: which tenant is this request for | `Arc.Tenancy`, configured below |
| **Membership**: may this caller use that tenant | You: authorize in a command, a query, an `Arc.Policy` or an `Arc.Filter` |
| **Storage isolation**: where the tenant's data lives | Chronicle (the event store namespace) and `cratis_arc_mongodb` (the database) |

A resolver only *selects*. A header, a query string value or a host is chosen by the caller, so none of them is evidence that the caller belongs to the tenant. Check membership before trusting it.

## Choose a resolver

```elixir
# From: Samples/showcase/config/runtime.exs
  tenancy: [resolver: :header],
```

The other resolvers take their options in the same keyword list, for example `tenancy: [resolver: :subdomain, base_domain: "myapp.com"]`.

| Resolver | Reads | Options |
| --- | --- | --- |
| `:header` (default) | a request header | `header`, default `"x-cratis-tenant-id"` |
| `:query` | a query string parameter | `query_parameter`, default `"tenantId"` |
| `:claim` | a claim of the authenticated principal | `claim_type`, default `"tenant_id"` |
| `:subdomain` | the label in front of a base domain | `base_domain` (required), falls back to the header |
| `:fixed`, `:development` | nothing: one tenant for every request | `tenant_id`, default `"development"` |
| a module | whatever it likes | implement `Arc.Tenancy` |

The `:claim` resolver reads the principal, so authentication must have run, and it is the one that ties selection to something the caller proved. The `:subdomain` resolver takes a tenant only from a host that is exactly one label in front of the base domain; everything else falls back to the header, which a client controls, so strip it at your ingress. The application refuses to start with a `:subdomain` resolver that has no usable base domain.

The result is `ctx.tenant`: a string, or `nil`. `nil`, an empty value and `"Default"` are all the **default tenant**.

## What the tenant selects

- **Chronicle.** A named tenant becomes the `namespace:` of every Chronicle call made through the context, so `Chronicle.all(Author, ctx.chronicle)` and the events a command appends go to that tenant's namespace. The default tenant uses the default namespace. An explicit `namespace:` in `chronicle:` wins.
- **MongoDB.** Each tenant is a database of its own. See [MongoDB](mongodb.md#tenancy).
- **Identity.** The identity details provider receives the tenant, `Arc.Identity.Context.tenant`, and `Arc.Identity.Context.context/1` turns it into an `Arc.Context`. The showcase reports it in its details:

```elixir
# From: Samples/showcase/lib/samples/identity/provider.ex
       tenant: if(Arc.Tenancy.default?(tenant), do: "Default", else: tenant)
```
- **Logging.** `:arc_tenant` is Logger metadata while an artifact runs.

## Develop with a tenant

`/.cratis/tenants` lists the tenants a development tool such as Lens can offer, from your `Arc.Identity.TenantsProvider`. It does not decide which tenant a request is for.
