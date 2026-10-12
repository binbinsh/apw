#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DENO_BIN:=deno}"
mkdir -p dist reports
"$DENO_BIN" check --frozen src/cli.ts
"$DENO_BIN" compile --frozen --allow-all -o dist/apw src/cli.ts
swiftc -O native/maintenance.swift -o dist/apw-maintenance \
  -framework AppKit -framework ApplicationServices -framework Security -framework CryptoKit
if [[ "${1:-}" == --verify ]]; then
  python3 tests/e2e_apw.py --bin "$PWD/dist/apw" --report "$PWD/reports/existing-cli.json"
  python3 tests/e2e_maintenance.py --bin "$PWD/dist/apw" --report "$PWD/reports/maintenance.json"
  python3 tests/e2e_native_contract.py --helper "$PWD/dist/apw-maintenance" --report "$PWD/reports/native-contract.json"
fi
# No browser start/stop, app activation, real credential writes, or tool download.
