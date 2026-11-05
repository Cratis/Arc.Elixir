#!/usr/bin/env bash
# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Usage: ./run.sh [dev|test]
#   dev    Vite dev server on http://localhost:${ARC_FRONTEND_PORT:-5173}, proxied to the Phoenix sample
#   test   type-checks and builds against the proxies the Phoenix sample generated
#          (run ../phoenix/run.sh test, or compile it, first)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

[ -d node_modules ] || npm ci --no-audit --no-fund --ignore-scripts
case "${1:-dev}" in
  dev) exec npm run dev ;;
  test) npm run build ;;
  *) echo "Usage: ./run.sh [dev|test]" >&2; exit 1 ;;
esac
