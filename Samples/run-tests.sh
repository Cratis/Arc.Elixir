#!/usr/bin/env bash
# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Builds and tests every sample against the Arc source in this repository.
#
#   plug      the smallest Arc application: Bandit and a Plug router
#   phoenix   Phoenix with the HTTP contract, LiveView and the SPA host; compiling it
#             generates the TypeScript proxies into the frontend sample
#   showcase  the samples of Arc on .NET, ported: a plug server and a React app; its MongoDB tests
#             run when a MongoDB replica set answers (MONGODB_URL) and are skipped otherwise
#   frontend  the React app, type-checked and built against those generated proxies
#
# The samples run against Chronicle's in-memory kernel in tests, so no Chronicle is needed here.
# Requires Elixir 1.18+, Node.js 22+ and npm.
set -euo pipefail

samples="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for sample in plug phoenix showcase; do
  echo "== $sample"
  cd "$samples/$sample"
  mix deps.get
  mix format --check-formatted
  MIX_ENV=test mix compile --warnings-as-errors
  mix test
done

echo "== showcase frontend (against the proxies the showcase generated)"
cd "$samples/showcase"
npm ci --no-audit --no-fund --ignore-scripts
npm run typecheck

echo "== frontend (against the proxies the phoenix sample generated)"
cd "$samples/frontend"
npm ci --no-audit --no-fund --ignore-scripts
npm run build
