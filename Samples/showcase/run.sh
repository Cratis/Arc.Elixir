#!/usr/bin/env bash
# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Each feature is a folder under lib/samples: its Elixir, its generated TypeScript proxies and its
# React page. The app shell is in frontend/.
#
# Usage: ./run.sh [start|dev|test]
#   start  starts MongoDB (docker compose), builds the React app into priv/spa and serves
#          everything from http://localhost:${PORT:-4002}
#   dev    starts MongoDB and the server, then the Vite dev server on http://localhost:5174
#   test   formats, compiles, tests the server (MongoDB tests run if MONGODB_URL answers,
#          else they are skipped) and type-checks the React app
# MONGODB_URL defaults to mongodb://localhost:27017/?replicaSet=rs0 (the compose file).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

mongo() {
  if command -v docker >/dev/null 2>&1; then
    docker compose up -d
  else
    echo "docker not found: the MongoDB page needs MongoDB at ${MONGODB_URL:-localhost:27017}" >&2
  fi
}
frontend() { ({ [ -d node_modules ] || npm ci --no-audit --no-fund --ignore-scripts; } && "$@"); }

case "${1:-start}" in
  start)
    mongo
    mix deps.get
    mix compile          # generates the TypeScript proxies beside each feature's Elixir, in lib/samples
    frontend npm run build
    exec mix run --no-halt
    ;;
  dev)
    mongo
    mix deps.get
    mix compile
    mix run --no-halt &
    server=$!
    trap 'kill $server 2>/dev/null' EXIT
    frontend npm run dev
    ;;
  test)
    mix deps.get
    mix format --check-formatted
    MIX_ENV=test mix compile --warnings-as-errors
    mix test
    frontend npm run typecheck
    ;;
  *) echo "Usage: ./run.sh [start|dev|test]" >&2; exit 1 ;;
esac
