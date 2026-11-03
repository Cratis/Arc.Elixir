---
id: 0009-keep-result-envelopes-and-identity-exact-to-the-contract
title: Keep the result envelopes and the identity capability exact to the Arc contract
status: accepted
stage: none
class: contract
reversibility: costly
decided: 2026-11-03
decider: Arc.Elixir repository owner
applies-to:
  - Source/arc/lib/arc/result.ex
  - Source/arc/lib/arc/identity*
  - Source/arc/lib/arc/plug/introspection.ex
  - Source/arc/lib/arc/authentication.ex
  - Source/arc/test/arc/envelope_test.exs
  - Source/arc/test/arc/identity_test.exs
---

<!-- Copyright (c) Cratis. All rights reserved. -->
<!-- Licensed under the MIT license. See LICENSE file in the project root for full license information. -->

## Context

`CommandResult` and `QueryResult` are the contract with the frontend: the React packages and every other Arc implementation depend on their exact shape. Identity is a second contract surface (`/.cratis/me`, the details schema, development users and tenants, the Microsoft identity platform headers). The first Elixir implementation covered identity only partly and gave the envelopes no spec of their own.

## Decision

- **The envelopes are frozen to the contract.** `Arc.CommandResult` and `Arc.QueryResult` produce exactly the fields, types and status ordering of the Arc HTTP contract. `Arc.EnvelopeTest` pins every key set (success, validation failure, authorization failure, exception, no data, paging) so a change is deliberate and reviewed. A failed result never carries `response` or `data`.
- **Identity is a capability, not an afterthought.**
  - `Arc.Identity.Provider` supplies typed details and is discovered from the application; the `details:` type drives `/.cratis/identity-details/schema` and the generated TypeScript class for `useIdentity`.
  - `GET /.cratis/me` answers 401 (not signed in) and 403 (provider refuses) with empty bodies, 200 with `{id, name, isAuthenticated, isAuthorized, roles, details}`, and every response is `no-store, private`.
  - `Arc.Identity.resolve/2` is the single implementation behind both the endpoint and `Arc.LiveView.assign_identity/2`.
  - `Arc.Identity.UsersProvider` and `TenantsProvider` feed `/.cratis/users` and `/.cratis/tenants` for tools such as Lens, concatenated without deduplication.
  - The five discovery routes share the `introspection` access setting; `/.cratis/me` does not.
  - `Arc.Authentication.MicrosoftIdentityPlatform` reads the unsigned `x-ms-client-principal*` headers only when `trust_forwarded_identity_headers: true`; otherwise the request stays anonymous and a warning is logged once.
- **Identity is presentation, not authorization.** Nothing in the details decides what a caller may do; `authorize` does.

## Options considered

- **Match the contract exactly (chosen).** The frontend packages need no change and cross-implementation clients keep working.
- **Idiomatic Elixir shapes on the wire.** Rejected: breaks the frontend contract for no user benefit.
- **A cookie-based identity fallback.** Rejected: Arc on .NET removed it as untrusted; this implementation never had it.

## Default if unanswered

The envelope and identity shapes stand. A future contract change is made in the shared Arc HTTP contract first, then here.

## Timeline and scope

Applies from the first release. Delta change sets remain out of scope (see the limits page). The signed forwarded-identity envelope was added by decision 0010.

## Verification

- **Done when:** `Arc.EnvelopeTest` and `Arc.IdentityTest` pass, and the contract run exercises the real `IdentityProvider` against an Arc server.
- **Verify by:** `mix test` in `Source/arc` and `ContractTests/run.sh`.

## Consequences

Any field added to an envelope fails a spec until the contract and the spec change together. Identity details types appear in generated proxies, so renaming one is a frontend-visible change.

## Evidence

- Cratis/Arc `Documentation/http-contract.md` (working copy): the envelope, identity and validation tables.
- Cratis/Arc `Source/DotNET/Arc.Core/Identity/*` and `Documentation/backend/csharp/identity/*` (working copy): provider flow, discovery routes and the Microsoft identity platform headers.
