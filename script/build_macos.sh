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
  python3 tests/e2e_password_read_shape.py --bin "$PWD/dist/apw" --report "$PWD/reports/password-read-shape.json"
  python3 tests/e2e_maintenance.py --bin "$PWD/dist/apw" --report "$PWD/reports/maintenance.json"
  python3 tests/e2e_journal_security.py --bin "$PWD/dist/apw" --report "$PWD/reports/journal-security.json"
  python3 tests/e2e_snapshot_security.py --bin "$PWD/dist/apw" --report "$PWD/reports/snapshot-security.json"
  python3 tests/e2e_native_contract.py --helper "$PWD/dist/apw-maintenance" --report "$PWD/reports/native-contract.json"
  python3 tests/e2e_native_policy.py --helper "$PWD/dist/apw-maintenance" --report "$PWD/reports/native-policy.json"
  python3 tests/e2e_native_synthetic_input_policy.py --helper "$PWD/dist/apw-maintenance" --report "$PWD/reports/native-synthetic-input-policy.json"
  python3 tests/e2e_native_synthetic_read_failure.py --helper "$PWD/dist/apw-maintenance" --report "$PWD/reports/native-synthetic-read-failure.json"
  python3 tests/e2e_native_context_classification.py --helper "$PWD/dist/apw-maintenance" --report "$PWD/reports/native-context-classification.json"
  python3 tests/e2e_capabilities.py --bin "$PWD/dist/apw" --report "$PWD/reports/capabilities.json"
  python3 tests/e2e_native_diagnostics.py --bin "$PWD/dist/apw" --report "$PWD/reports/native-diagnostics.json"
  python3 tests/e2e_delete_confirmation_diagnostics.py --bin "$PWD/dist/apw" --report "$PWD/reports/delete-confirmation-diagnostics.json"
  python3 tests/e2e_editor_recovery.py --bin "$PWD/dist/apw" --report "$PWD/reports/editor-recovery.json"
  python3 tests/e2e_notes_probe.py --bin "$PWD/dist/apw" --report "$PWD/reports/notes-probe.json"
  python3 tests/e2e_synthetic_foreground_notes.py --bin "$PWD/dist/apw" --report "$PWD/reports/synthetic-foreground-notes.json"
  python3 tests/e2e_apple_notes_probe_runner.py --bin "$PWD/dist/apw" --report "$PWD/reports/apple-notes-probe-runner.json"
  python3 tests/e2e_batch_acceptance.py --bin "$PWD/dist/apw" --report "$PWD/reports/batch-acceptance.json"
fi
# No browser start/stop, app activation, real credential writes, or tool download.
