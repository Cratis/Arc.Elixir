#!/usr/bin/env bash
# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# The proxy contract gate. It proves, in order, that the generated TypeScript:
#   1. is deterministic (generating twice changes nothing),
#   2. compiles under strict TypeScript with verbatimModuleSyntax against the published
#      @cratis/arc, @cratis/arc.react and @cratis/fundamentals packages, and
#   3. works at runtime: the real Arc client executes commands and queries and receives
#      observable-query pushes from an Arc for Elixir server.
#
# Requires Elixir 1.18+, Node.js 22+ and npm. Run from anywhere.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${ARC_ELIXIR_CONTRACT_PORT:-4747}"
log="$(mktemp)"

hash_generated() {
  find "$root/ContractTests/TypeScript/generated" -type f -name '*.ts' -print0 | sort -z | xargs -0 sha256sum | sha256sum
}

cd "$root/Source/arc"
export MIX_ENV=test
mix deps.get >/dev/null

echo "== Generate proxies"
mix run ../../ContractTests/generate.exs
first="$(hash_generated)"
mix run ../../ContractTests/generate.exs >/dev/null
second="$(hash_generated)"
if [ "$first" != "$second" ]; then
  echo "Generated proxies changed between consecutive generations." >&2
  exit 1
fi

echo "== Compile the proxies under strict TypeScript"
cd "$root/ContractTests/TypeScript"
npm ci --no-audit --no-fund --ignore-scripts
npx tsc --noEmit

echo "== Run the real client against an Arc for Elixir server"
cd "$root/Source/arc"
PORT="$port" mix run ../../ContractTests/server.exs >"$log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true; rm -f "$log"' EXIT

for _ in $(seq 1 90); do
  if grep -q '^ARC_READY' "$log"; then break; fi
  if ! kill -0 "$server" 2>/dev/null; then
    cat "$log" >&2
    echo "The contract server stopped." >&2
    exit 1
  fi
  sleep 1
done
grep -q '^ARC_READY' "$log" || { cat "$log" >&2; echo "The contract server did not start." >&2; exit 1; }

cd "$root/ContractTests/TypeScript"
ARC_ELIXIR_ORIGIN="http://localhost:$port" npm run test:runtime
