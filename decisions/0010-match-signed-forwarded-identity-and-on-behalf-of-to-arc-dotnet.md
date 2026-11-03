---
id: 0010-match-signed-forwarded-identity-and-on-behalf-of-to-arc-dotnet
title: Match signed forwarded identity and on-behalf-of to Arc on .NET
status: accepted
stage: none
class: contract
reversibility: costly
decided: 2026-11-03
decider: Arc.Elixir repository owner
applies-to:
  - Source/arc/lib/arc/identity/**
  - Source/arc/lib/arc/authentication.ex
  - Documentation/authorization-and-identity.md
---

<!-- Copyright (c) Cratis. All rights reserved. -->
<!-- Licensed under the MIT license. See LICENSE file in the project root for full license information. -->

> Amends [0009](0009-keep-result-envelopes-and-identity-exact-to-the-contract.md): the signed forwarded envelope is no longer out of scope.

## Context

Arc on .NET verifies an HMAC-SHA256 forwarded-identity envelope and an RS256 on-behalf-of assertion, so an ingress can prove identity headers without the application trusting the network. The owner asked for parity.

## Decision

- `Arc.Authentication.MicrosoftIdentityPlatform` (renamed from `ClientPrincipal`) implements the unsigned path and the signed path with the same canonical bytes, freshness window, replay rules and key limits as Arc on .NET.
- On-behalf-of validates the RS256 assertion with the same claim, lifetime, hash, method, path, tenant and service checks. The actor is carried on `Arc.Principal` and recorded in Chronicle as the cause, on behalf of the user.
- Replay memory is process-local, kept by a process under `Arc.Application`, and fails closed when absent.
- Both features are off by default.

## Options considered

- **Match Arc on .NET exactly (chosen).** An ingress written for one implementation works with the other.
- **Trust headers only.** Rejected: the owner required parity, and it needs a trusted network.

## Default if unanswered

Keep the defaults off and document the per-node replay limit.

## Timeline and scope

Applies until superseded.

## Verification

- **Done when:** the interop vector from the Arc on .NET documentation verifies, and each rejection path has a spec.
- **Verify by:** `mix test` in `Source/arc` (`signed_forwarding_test`, `on_behalf_of_test`).

## Consequences

An Arc for Elixir service can sit behind the same ingress as an Arc on .NET service. Replay protection is not shared across nodes.

## Evidence

- The Arc on .NET forwarded-identity documentation and its published interop vector, matched by `signed_forwarding_test`.
