#!/usr/bin/env bash
# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Usage: ./run.sh [start|dev|test]
#   start  builds the React app into priv/spa and runs Phoenix, which serves it, on
#          http://localhost:${PORT:-4000} (the LiveView page is at /live/authors)
#   dev    runs Phoenix and the Vite dev server, with hot reload, on http://localhost:5173
#   both   start the Chronicle development image with Docker when none is running (or set
#          CHRONICLE_CONNECTION_STRING). Compiling generates the TypeScript proxies into
#          ../frontend/src/arc
#   test   formats, compiles with warnings as errors and tests, with Chronicle's in-memory kernel
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# Chronicle must answer on the connection string's host and port. Start the development image
# when nothing listens there and Docker is available.
chronicle() {
  local port=35000
  if (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null; then return; fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "Chronicle is not running on localhost:$port and Docker was not found." >&2
    echo "Start Chronicle, or set CHRONICLE_CONNECTION_STRING." >&2
    exit 1
  fi
  echo "Starting Chronicle on localhost:$port ..."
  docker start chronicle >/dev/null 2>&1 || docker run -d --name chronicle \
    -p 127.0.0.1:$port:$port cratis/chronicle:latest-development >/dev/null
  for _ in $(seq 1 60); do
    (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null && return
    sleep 1
  done
  echo "Chronicle did not start in time: docker logs chronicle" >&2
  exit 1
}

# Builds the React app, against the generated proxies, into priv/spa where Phoenix serves it.
spa() {
  (cd ../frontend &&
    { [ -d node_modules ] || npm ci --no-audit --no-fund --ignore-scripts; } &&
    ARC_SPA_OUT="$PWD/../phoenix/priv/spa" npm run build)
}

# The gRPC client lists the optional :gun adapter as undefined while it compiles. It is not used,
# so show the compilation only when it fails.
deps() {
  mix deps.get >/dev/null
  mix deps.compile >/tmp/arc-sample-deps.log 2>&1 || { cat /tmp/arc-sample-deps.log; exit 1; }
}

case "${1:-start}" in
  start)
    chronicle
    deps
    mix compile            # generates the proxies the React app is built on
    spa
    echo
    echo "  React app:  http://localhost:${PORT:-4000}"
    echo "  LiveView:   http://localhost:${PORT:-4000}/live/authors  (add ?as=ed&roles=editor to rename)"
    echo
    exec mix phx.server
    ;;
  dev)
    chronicle
    deps
    mix compile
    mix phx.server &
    server=$!
    trap 'kill $server 2>/dev/null' EXIT
    echo
    echo "  React app (hot reload):  http://localhost:5173"
    echo
    (cd ../frontend && { [ -d node_modules ] || npm ci --no-audit --no-fund --ignore-scripts; } && npm run dev)
    ;;
  test)
    deps
    mix format --check-formatted
    MIX_ENV=test mix compile --warnings-as-errors
    mix test
    ;;
  *) echo "Usage: ./run.sh [start|dev|test]" >&2; exit 1 ;;
esac
