#!/usr/bin/env bash
# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Usage: ./run.sh [start|test]
#   start  runs the server on http://localhost:${PORT:-4001}; starts the Chronicle development image with Docker
#          when none is running (or set CHRONICLE_CONNECTION_STRING)
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
    exec mix run --no-halt
    ;;
  test)
    deps
    mix format --check-formatted
    MIX_ENV=test mix compile --warnings-as-errors
    mix test
    ;;
  *) echo "Usage: ./run.sh [start|test]" >&2; exit 1 ;;
esac
